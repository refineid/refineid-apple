// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// A card operation the requester asks the paired proxy to perform.
  public enum RappRequesterOperation: Sendable, Equatable {
    case browserAuthentication(
      displayContext: String,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digest: Data
    )
    case documentSigning(
      documentName: String,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digest: Data
    )
    case readAuthenticationCertificate
    case readSignatureCertificate

    /// The answer `result` carries, when its kind is the one this
    /// operation asked for.
    public func response(for result: RappOperationResult) -> RappRequesterResponse? {
      switch (self, result) {
      case (.readAuthenticationCertificate, .certificate(let der)):
        der.isEmpty ? nil : .authenticationCertificate(der)

      case (.readSignatureCertificate, .certificate(let der)):
        der.isEmpty ? nil : .signatureCertificate(der)

      case (.browserAuthentication, .signature(let signature)),
        (.documentSigning, .signature(let signature)):
        signature.isEmpty ? nil : .signature(signature)

      default:
        nil
      }
    }
  }

  extension RappConnectionCoordinator {
    /// Asks the custodian for `operation`, granting it `lifetime`
    /// milliseconds.
    public func begin(_ operation: RappRequesterOperation, lifetime: UInt64) async throws {
      switch operation {
      case .readAuthenticationCertificate:
        try await beginReadCertificate(
          signatureCertificate: false, expiresAfterMilliseconds: lifetime)

      case .readSignatureCertificate:
        try await beginReadCertificate(
          signatureCertificate: true, expiresAfterMilliseconds: lifetime)

      case .browserAuthentication(let context, let keyProfile, let algorithm, let digest):
        try await beginBrowserAuthentication(
          origin: context, keyProfile: keyProfile, algorithm: algorithm, digest: digest,
          expiresAfterMilliseconds: lifetime)

      case .documentSigning(let documentName, let keyProfile, let algorithm, let digest):
        try await beginSignDocument(
          documentName: documentName, keyProfile: keyProfile, algorithm: algorithm,
          digest: digest, expiresAfterMilliseconds: lifetime)
      }
    }
  }
#endif
