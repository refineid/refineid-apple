// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoKit
import Foundation
import OSLog
import Security

extension DocumentSigner {
  private enum RemoteSigningPolicy {
    static let maximumCertificateAttempts = 3
    static let maximumSigningAttempts = 5
    static let retryDelaySeconds: TimeInterval = 1.0
    static let settleDelaySeconds: TimeInterval = 1.0
  }

  #if DEBUG
    private static let logger = Logger(
      subsystem: "fi.refineid.ReFineID", category: "document-signer"
    )
  #endif

  /// A selected RAPP phone is the signing device only while remote use is
  /// on and no card is in a local reader: a local card overrides the phone.
  ///
  /// The two paths never silently retry one another after an
  /// authenticated or credential-bearing operation has begun.
  @MainActor internal static var usesRappSigning: Bool {
    #if REFINEID_REMOTE_CARD
      !SupportedCardTransports.offersNearField
        && PersistentTokenRegistry.remoteUseOn
        && !CardPresence.shared.isReaderCardPresent
        && (try? RappDeviceVault().selectedPairID()) != nil
    #else
      false
    #endif
  }

  /// Builds the same locally verified card material as the reader path while
  /// delegating only the certificate read and PIN 2 card signature to the
  /// explicitly paired phone.
  internal static func remoteCardMaterial(
    prepared: PdfSignaturePlaceholder,
    documentName: String,
    byteRangeDigest: Data,
    expectedCertificate: Data?
  ) async throws -> CardMaterial {
    let product = try await Self.remoteQualifiedSignature(
      documentName: documentName,
      expectedCertificate: expectedCertificate
    ) { certificate in
      QualifiedDocumentCms.signedAttributes(
        byteRangeDigest: byteRangeDigest,
        signerCertificate: certificate
      )
    }
    return CardMaterial(
      placeholder: prepared,
      signedAttributes: product.content,
      signature: product.signature,
      certificate: product.certificate,
      profile: product.profile
    )
  }

  /// Fetches the qualified signature certificate from the paired phone
  /// with retries, leaving the phone a moment before the next request.
  internal static func fetchRemoteSignatureCertificate(
    displayName: String
  ) async throws -> Data {
    var certificate: Data?
    var certificateError: Error?
    for attempt in 1...RemoteSigningPolicy.maximumCertificateAttempts {
      do {
        let certificateResponse = try await Self.askPhone(
          .readSignatureCertificate, displayName: displayName)
        if case .signatureCertificate(let cert) = certificateResponse {
          certificate = cert
          break
        }
      } catch let error as RappRequesterClientError {
        certificateError = error
        guard Self.isRecoverableRemoteError(error),
          attempt < RemoteSigningPolicy.maximumCertificateAttempts
        else {
          throw error
        }
        try? await Task.sleep(for: .seconds(RemoteSigningPolicy.retryDelaySeconds))
      } catch {
        throw error
      }
    }
    guard let certificate else {
      throw certificateError ?? Failure.remote(.noSignature)
    }
    try? await Task.sleep(for: .seconds(RemoteSigningPolicy.settleDelaySeconds))
    return certificate
  }

  /// Runs `operation` on the paired phone: on this computer's one session
  /// with it where the build holds one, so signing never opens a second
  /// session beside it; else on a session of its own.
  private static func askPhone(
    _ operation: RappRequesterOperation, displayName: String
  ) async throws -> RappRequesterResponse {
    #if REFINEID_STREAM_TRANSPORT
      return try await PersistentTokenRegistry.shared.perform(operation)
    #else
      return try await Task.detached(priority: .userInitiated) {
        try RappPersistentRequesterClient(displayName: displayName).perform(operation)
      }.value
    #endif
  }

  /// Performs one remote qualified-signature operation.
  ///
  /// The requester sends only the digest and public algorithm metadata;
  /// PIN 2 exists solely in the phone authorization UI and its NFC card
  /// session.
  internal static func remoteQualifiedSignature(
    documentName: String,
    expectedCertificate: Data?,
    content: @escaping @Sendable (Data) -> Data
  ) async throws -> CardMaintenance.QualifiedProduct {
    Self.report(.phone)
    let certificate: Data
    if let expectedCertificate {
      certificate = expectedCertificate
    } else {
      certificate = try await Self.remoteSignatureCertificate()
    }
    guard
      CardMaintenance.qualifiedCertificate(
        certificate, matches: expectedCertificate
      )
    else {
      throw Failure.stampSignerChanged
    }
    do {
      return try await Self.executeRemoteQualifiedSignature(
        documentName: documentName,
        certificate: certificate,
        content: content)
    } catch Failure.remote(.unverifiedSignature) {
      // The card on the phone is not the one the certificate was read
      // from; the next signature reads it again.
      await Self.remoteCertificates.forget()
      throw Failure.remote(.unverifiedSignature)
    }
  }

  private static func executeRemoteQualifiedSignature(
    documentName: String,
    certificate: Data,
    content: (Data) -> Data
  ) async throws -> CardMaintenance.QualifiedProduct {
    let displayName = ProcessInfo.processInfo.hostName
    guard
      let securityCertificate = SecCertificateCreateWithData(
        nil, certificate as CFData
      ),
      let publicKey = SecCertificateCopyKey(securityCertificate),
      let profile = CardKeyProfile.resolve(fromPublicKey: publicKey)
    else {
      throw Failure.remote(.unusableCertificate)
    }

    let signedContent = content(certificate)
    let digest = Data(SHA384.hash(data: signedContent))
    guard
      let request = profile.qualifiedDocumentRequest(digest: digest),
      let remoteAlgorithm = RappOperationDriver.SignatureAlgorithm(request.algorithm)
    else {
      throw Failure.remote(.unusableCertificate)
    }

    let signature = try await Self.executeRemoteDocumentSigning(
      displayName: displayName,
      documentName: documentName,
      keyProfile: RappOperationDriver.KeyProfile(profile),
      algorithm: remoteAlgorithm,
      digest: digest
    )
    guard let wireSignature = request.verifiedRemoteSignature(signature, from: publicKey) else {
      throw Failure.remote(.unverifiedSignature)
    }
    return CardMaintenance.QualifiedProduct(
      signature: wireSignature,
      content: signedContent,
      certificate: certificate,
      profile: profile
    )
  }

  /// Sends the document signing request to the paired phone, retrying transparently
  /// when the transport connection drops or the peer was not found before authorization.
  private static func executeRemoteDocumentSigning(
    displayName: String,
    documentName: String,
    keyProfile: RappOperationDriver.KeyProfile,
    algorithm: RappOperationDriver.SignatureAlgorithm,
    digest: Data
  ) async throws -> Data {
    var signingError: Error?
    for attempt in 1...RemoteSigningPolicy.maximumSigningAttempts {
      do {
        trace("remote signing attempt \(attempt)/\(RemoteSigningPolicy.maximumSigningAttempts)")
        let signatureResponse = try await Self.askPhone(
          .documentSigning(
            documentName: documentName,
            keyProfile: keyProfile,
            algorithm: algorithm,
            digest: digest
          ),
          displayName: displayName)
        if case .signature(let signature) = signatureResponse {
          trace("remote signing succeeded: \(signature.count) bytes")
          return signature
        }
        throw Failure.remote(.noSignature)
      } catch let error as RappRequesterClientError {
        signingError = error
        trace("attempt \(attempt) failed: \(error)")
        guard Self.isRecoverableRemoteError(error),
          attempt < RemoteSigningPolicy.maximumSigningAttempts
        else {
          throw error
        }
        try? await Task.sleep(for: .seconds(RemoteSigningPolicy.retryDelaySeconds))
      } catch {
        trace("attempt \(attempt) non-client error: \(error)")
        throw error
      }
    }
    guard let signingError else { throw Failure.remote(.noSignature) }
    throw signingError
  }

  /// Debug builds trace the remote exchange; release builds say nothing.
  private static func trace(_ message: String) {
    #if DEBUG
      logger.notice("[DocumentSigner] \(message, privacy: .public)")
    #endif
  }

  /// Whether another attempt may succeed.
  ///
  /// It may when the session dropped, or, where each attempt dials a
  /// session of its own, when the phone was not found in that dial's
  /// window; the held session already waited out its own.
  private static func isRecoverableRemoteError(_ error: RappRequesterClientError) -> Bool {
    switch error {
    case .transport, .protocolFailure:
      return true

    case .peerNotFound:
      #if REFINEID_STREAM_TRANSPORT
        return false
      #else
        return true
      #endif

    case .noActivePair, .noSelectedPair, .terminal, .timedOut,
      .unexpectedResult:
      return false
    }
  }
}
