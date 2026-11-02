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
    // Only the phone's own field is opened with the primed card's access
    // number; a reader may hold any card.
    let primedAccessNumber = transport == .nearField ? cardAccessNumber : nil
    let cached = primedAccessNumber.flatMap { accessNumber in
      PrimeStore.signatureCertificate(cardAccessNumber: accessNumber)
    }
    let result = await onCard(
      transport: transport,
      opener: .pin(.pin2(pin2), cardAccessNumber: cardAccessNumber) { outcome in
        .refused(outcome)
      },
      operation: .signature,
      failedStep: Self.failedStep(of:)
    ) { operations in
      Self.qualifiedInSession(
        operations,
        pin2: pin2,
        cachedCertificate: cached,
        expectedCertificate: expectedCertificate,
        builder: contentBuilder
      )
    }
    if case .signed(let product)? = result, cached == nil, let primedAccessNumber {
      PrimeStore.updateSignatureCertificate(
        product.certificate, cardAccessNumber: primedAccessNumber)
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
  ///
  /// A channel PIN 2 opened (an organization card on an antenna) has
  /// already passed the floor and counts as PIN 2 verified, so it is
  /// neither probed nor verified again; the card then signs in DF.ESIGN,
  /// selected afresh after the certificate read (FINEID S4-2 v4.0
  /// section 4.6.21).
  private static func qualifiedInSession(
    _ operations: CardOperations,
    pin2: String,
    cachedCertificate: Data?,
    expectedCertificate: Data?,
    builder: (Data) -> Data
  ) -> QualifiedAnswer {
    let openedByPin2 = operations.channelPin == .pin2
    if !openedByPin2, let refusal = Self.floorRefusal(operations) {
      return refusal
    }
    guard let identity = Self.qualifiedIdentity(cachedCertificate, operations) else {
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
    if let refusal = Self.authorization(operations, pin2: pin2, openedByPin2: openedByPin2) {
      return refusal
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

  /// The retry floor's refusal of PIN 2.
  ///
  /// Read with the counter-safe probe; nil when PIN 2 may be presented.
  private static func floorRefusal(_ operations: CardOperations) -> QualifiedAnswer? {
    guard let probe = try? operations.probeRetryCounter(role: .pin2) else {
      return .refused(.floorRefused(.refuseUnreadable))
    }
    let verdict = RetryFloor.evaluate(probeOutcome: probe)
    guard verdict == .proceed else {
      return .refused(.floorRefused(verdict))
    }
    return nil
  }

  /// Authorizes the one signature.
  ///
  /// VERIFY PIN 2, or, in a channel PIN 2 opened, the signature directory
  /// made current. Nil when the card may sign.
  private static func authorization(
    _ operations: CardOperations,
    pin2: String,
    openedByPin2: Bool
  ) -> QualifiedAnswer? {
    if openedByPin2 {
      return (try? operations.selectEsignDirectory()) == nil ? .refused(.failed) : nil
    }
    guard let credential = Pin2(digits: pin2) else {
      return .refused(.invalidEntry)
    }
    do {
      try operations.verifyPin2(credential.consumeForSingleTransmission())
    } catch {
      return .refused(outcome(of: error))
    }
    return nil
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
    _ = TrustRootsCache.shared.issuer(
      for: leaf,
      cardIssuer: { try? operations.readCertificate(.issuing) },
      cardRoot: { try? operations.readCertificate(.root) }
    )
  }

  /// The qualified certificate: the cached one, or else read from either
  /// of its locations on the card, without spending PIN2.
  internal static func qualifiedCertificate(
    cached: Data?,
    operations: CardOperations
  ) -> Data? {
    if let cached { return cached }
    return (try? operations.readCertificate(.qualifiedSignature))
      ?? (try? operations.readCertificate(.secondQualifiedSignature))
  }

  /// Classifies the cached qualified certificate, or else the one read
  /// from the card.
  private static func qualifiedIdentity(
    _ cached: Data?,
    _ operations: CardOperations
  ) -> QualifiedIdentity? {
    guard
      let certificate = Self.qualifiedCertificate(cached: cached, operations: operations),
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
