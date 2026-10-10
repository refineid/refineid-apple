// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(MultipeerConnectivity)
  import Foundation

  @testable import CardCore

  /// Says what the slim relay can ask for, and reads what comes back.
  ///
  /// Two operations, which are the two a browser identity needs: the
  /// certificate it offers, and the signature that proves the key. Document
  /// signing is not here, because it needs a PIN entered per signature and
  /// the slim message set carries no place to put one.
  public enum SignRelayOperation {
    /// The request that carries `operation`, or nil when the slim relay has
    /// no message for it.
    ///
    /// - Parameters:
    ///   - operation: what the caller wants from the card.
    ///   - requestID: the identifier correlating request and answer.
    /// - Returns: the message to send, or nil when unsupported.
    public static func request(
      for operation: RappRequesterOperation,
      requestID: UUID
    ) -> PersistentRelayMessage? {
      switch operation {
      case .readAuthenticationCertificate:
        .identityRequest(requestID: requestID)

      case .browserAuthentication(_, let keyProfile, let algorithm, let digest):
        profiled(
          requestID: requestID, keyProfile: keyProfile, algorithm: algorithm, digest: digest)

      case .readSignatureCertificate, .documentSigning:
        nil
      }
    }

    /// What `answer` means for `operation`, or nil when it answers something
    /// else.
    ///
    /// - Parameters:
    ///   - answer: the peer's message.
    ///   - operation: what was asked for.
    /// - Returns: the response to hand the caller, or nil.
    public static func response(
      from answer: PersistentRelayMessage,
      for operation: RappRequesterOperation
    ) -> RappRequesterResponse? {
      switch (operation, answer) {
      case (.readAuthenticationCertificate, .identityResponse(_, let der, let cardSerial)):
        der.isEmpty ? nil : .authenticationCertificate(der, cardSerial: cardSerial)

      case (.browserAuthentication, .signatureResponse(_, let signature)):
        signature.isEmpty ? nil : .signature(signature)

      default:
        nil
      }
    }

    private static func profiled(
      requestID: UUID,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digest: Data
    ) -> PersistentRelayMessage? {
      guard let wireAlgorithm = PersistentRelaySigningAlgorithm(algorithm.signingAlgorithm) else {
        return nil
      }
      return .signatureRequest(
        requestID: requestID,
        profile: PersistentRelayCardProfile(keyProfile.cardKeyProfile),
        algorithm: wireAlgorithm,
        digest: digest
      )
    }
  }
#endif
