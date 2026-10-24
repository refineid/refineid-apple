// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoKit
import Foundation
import Security

/// The PIN2-gated qualified-signature operation.
extension CardMaintenance {
  /// What one qualified signing session produced.
  internal struct QualifiedProduct {
    /// The locally verified signature value written to CMS.
    internal let signature: Data

    /// The exact bytes hashed and signed.
    internal let content: Data

    /// The certificate that will verify it.
    internal let certificate: Data

    /// The certificate-bound card profile written to CMS.
    internal let profile: CardKeyProfile
  }

  /// The result of one qualified signing session.
  internal enum QualifiedAnswer {
    /// The card refused, at the floor or at the credential.
    case refused(Outcome)

    /// The present card is not the one that supplied the visible stamp.
    case signerCertificateMismatch

    /// The card signed.
    case signed(QualifiedProduct)
  }

  /// Certificate material selected before a PIN is spent.
  private struct QualifiedIdentity {
    let certificate: Data
    let publicKey: SecKey
    let profile: CardKeyProfile
  }

  /// Reads the qualified certificate, verifies PIN2 and signs the
  /// attributes the caller builds from it - one session, one PIN2,
  /// one signature.
  ///
  /// The attributes cannot be built before the session because they
  /// hash the certificate, and the certificate is on the card.
  internal static func qualifiedSignature(
    pin2: String,
    expectedCertificate: Data?,
    transport: Transport,
    cardAccessNumber: String?,
    contentBuilder: @escaping @Sendable (Data) -> Data
  ) async -> QualifiedAnswer {
    let result = await onCard(
      transport: transport,
      cardAccessNumber: cardAccessNumber,
      operation: .signature,
      failedStep: Self.failedStep(of:)
    ) { operations in
      Self.qualifiedInSession(
        operations,
        pin2: pin2,
        expectedCertificate: expectedCertificate,
        builder: contentBuilder
      )
    }
    return result ?? .refused(.noCard)
  }

  /// Where on the meter a qualified signing session broke; nil when the
  /// card signed.
  private static func failedStep(of answer: QualifiedAnswer) -> NearFieldStep? {
    switch answer {
    case .signed:
      nil

    case .signerCertificateMismatch:
      .certificate

    case .refused(.failed):
      .signature

    case .refused:
      .credential
    }
  }

  /// The qualified signature, inside an open session: floor, the
  /// certificate, PIN2, then the one signature it authorises.
  private static func qualifiedInSession(
    _ operations: CardOperations,
    pin2: String,
    expectedCertificate: Data?,
    builder: (Data) -> Data
  ) -> QualifiedAnswer {
    guard let probe = try? operations.probeRetryCounter(role: .pin2) else {
      return .refused(.floorRefused(.refuseUnreadable))
    }
    let verdict = RetryFloor.evaluate(probeOutcome: probe)
    guard verdict == .proceed else {
      return .refused(.floorRefused(verdict))
    }
    guard let identity = Self.qualifiedIdentity(operations) else {
      return .refused(.failed)
    }
    Self.cacheCardAuthorities(for: identity.certificate, operations: operations)
    guard
      Self.qualifiedCertificate(
        identity.certificate, matches: expectedCertificate
      )
    else {
      return .signerCertificateMismatch
    }
    guard let credential = Pin2(digits: pin2) else {
      return .refused(.invalidEntry)
    }
    do {
      try operations.verifyPin2(credential.consumeForSingleTransmission())
    } catch {
      return .refused(outcome(of: error))
    }
    let content = builder(identity.certificate)
    let digest = Data(SHA384.hash(data: content))
    guard
      let request = identity.profile.qualifiedDocumentRequest(digest: digest),
      let rawSignature = try? operations.computeQualifiedSignature(
        overDigest: digest,
        algorithm: request.algorithm,
        expectedSignatureLength: request.expectedSignatureLength
      ),
      let signature = request.wireSignature(from: rawSignature),
      request.isSatisfied(by: signature, from: identity.publicKey)
    else {
      return .refused(.failed)
    }
    return .signed(
      QualifiedProduct(
        signature: signature,
        content: content,
        certificate: identity.certificate,
        profile: identity.profile
      )
    )
  }

  /// Whether the card certificate is the exact one a visible stamp states.
  ///
  /// A nil expectation is the unstamped path and accepts any signer.
  internal static func qualifiedCertificate(
    _ certificate: Data,
    matches expectedCertificate: Data?
  ) -> Bool {
    expectedCertificate.map { certificate == $0 } ?? true
  }

  /// Caches the card's issuing and root certificates in this process.
  ///
  /// The evidence walk ends only at an explicitly approved anchor,
  /// and this session's process holds none until the card is asked.
  /// Best effort: a card without those files still signs, and the
  /// walk reports the missing anchor instead of partial evidence.
  private static func cacheCardAuthorities(
    for leaf: Data,
    operations: CardOperations
  ) {
    guard TrustRootsCache.shared.der(matching: leaf) == nil else { return }
    let issuer = try? operations.readCertificate(.issuing)
    let root = try? operations.readCertificate(.root)
    _ = TrustRootsCache.shared.ensureIssuer(
      for: leaf, cardIssuer: issuer, cardRoot: root
    )
  }

  /// Reads and classifies the qualified certificate without spending PIN2.
  private static func qualifiedIdentity(
    _ operations: CardOperations
  ) -> QualifiedIdentity? {
    guard
      let certificate = (try? operations.readCertificate(.qualifiedSignature))
        ?? (try? operations.readCertificate(.secondQualifiedSignature)),
      let securityCertificate = SecCertificateCreateWithData(
        nil, certificate as CFData
      ),
      let publicKey = SecCertificateCopyKey(securityCertificate),
      let profile = CardKeyProfile.resolve(fromPublicKey: publicKey)
    else {
      return nil
    }
    return QualifiedIdentity(
      certificate: certificate, publicKey: publicKey, profile: profile
    )
  }
}
