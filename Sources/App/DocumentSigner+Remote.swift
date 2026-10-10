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

  private final class RemoteCertificateCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: Data?

    fileprivate func get() -> Data? {
      lock.withLock { cached }
    }

    fileprivate func set(_ data: Data) {
      lock.withLock { cached = data }
    }
  }

  #if DEBUG
    private static let logger = Logger(
      subsystem: "fi.refineid.ReFineID", category: "document-signer"
    )
  #endif
  private static let remoteSignatureCertificateCache = RemoteCertificateCache()

  /// A selected RAPP phone is the signing device only when no local reader
  /// card is ready.
  ///
  /// The two paths never silently retry one another after an
  /// authenticated or credential-bearing operation has begun.
  @MainActor internal static var usesRappSigning: Bool {
    #if REFINEID_REMOTE_CARD
      !SupportedCardTransports.offersNearField
        && !CardPresence.shared.isReaderCardReady
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
    byteRangeDigest: Data,
    expectedCertificate: Data?
  ) async throws -> CardMaterial {
    let product = try await Self.remoteQualifiedSignature(
      documentName: String(
        localized: "Document",
        defaultValue: "Document",
        table: "DocumentSigning"
      ),
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

  /// Fetches the qualified signature certificate from the paired phone with retries.
  private static func fetchRemoteSignatureCertificate(
    displayName: String
  ) throws -> Data {
    var certificate: Data?
    var certificateError: Error?
    for attempt in 1...RemoteSigningPolicy.maximumCertificateAttempts {
      do {
        let certificateClient = RappPersistentRequesterClient(displayName: displayName)
        let certificateResponse = try certificateClient.perform(.readSignatureCertificate)
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
        Thread.sleep(forTimeInterval: RemoteSigningPolicy.retryDelaySeconds)
      } catch {
        throw error
      }
    }
    guard let certificate else {
      throw certificateError ?? Failure.remote(.noSignature)
    }
    return certificate
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
    try await Task.detached(priority: .userInitiated) {
      try Self.executeRemoteQualifiedSignature(
        documentName: documentName,
        expectedCertificate: expectedCertificate,
        content: content)
    }.value
  }

  private static func resolveRemoteCertificate(
    displayName: String,
    expectedCertificate: Data?
  ) throws -> Data {
    let certificate: Data
    if let expectedCertificate {
      certificate = expectedCertificate
    } else if let cached = remoteSignatureCertificateCache.get() {
      certificate = cached
    } else {
      let fetched = try Self.fetchRemoteSignatureCertificate(displayName: displayName)
      remoteSignatureCertificateCache.set(fetched)
      certificate = fetched
      Thread.sleep(forTimeInterval: RemoteSigningPolicy.settleDelaySeconds)
    }
    guard
      CardMaintenance.qualifiedCertificate(
        certificate, matches: expectedCertificate
      )
    else {
      throw Failure.stampSignerChanged
    }
    return certificate
  }

  private static func executeRemoteQualifiedSignature(
    documentName: String,
    expectedCertificate: Data?,
    content: (Data) -> Data
  ) throws -> CardMaintenance.QualifiedProduct {
    let displayName = ProcessInfo.processInfo.hostName
    let certificate = try Self.resolveRemoteCertificate(
      displayName: displayName,
      expectedCertificate: expectedCertificate
    )
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

    let signature = try Self.executeRemoteDocumentSigning(
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
  ) throws -> Data {
    var signingError: Error?
    for attempt in 1...RemoteSigningPolicy.maximumSigningAttempts {
      do {
        trace("remote signing attempt \(attempt)/\(RemoteSigningPolicy.maximumSigningAttempts)")
        let signingClient = RappPersistentRequesterClient(displayName: displayName)
        let signatureResponse = try signingClient.perform(
          .documentSigning(
            documentName: documentName,
            keyProfile: keyProfile,
            algorithm: algorithm,
            digest: digest
          )
        )
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
        Thread.sleep(forTimeInterval: RemoteSigningPolicy.retryDelaySeconds)
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

  private static func isRecoverableRemoteError(_ error: RappRequesterClientError) -> Bool {
    switch error {
    case .transport, .peerNotFound, .protocolFailure:
      true

    case .noActivePair, .noSelectedPair, .terminal, .timedOut,
      .unexpectedResult:
      false
    }
  }
}
