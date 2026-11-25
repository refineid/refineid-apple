// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation

  /// Interactive Web eID card command execution (authentication, signing
  /// certificate export, and qualified signing).
  extension WebEidCardRunner {
    /// Verifies PIN 1, signs the Web eID authentication digest, and locally
    /// verifies the resulting raw signature before returning the token payload.
    internal static func executeAuthenticate(
      origin: WebEidOrigin,
      challengeNonce: String,
      pin1: String,
      expectedChipSerial: ChipSerial
    ) async -> Result<WebEidResponsePayload, WebEidCardFailure> {
      guard Pin1(digits: pin1) != nil else {
        return .failure(.invalidPinEntry)
      }
      let answer: Result<WebEidResponsePayload, WebEidCardFailure>? =
        await CardMaintenance.onReader { operations in
          authenticateInSession(
            operations,
            origin: origin,
            challengeNonce: challengeNonce,
            pinDigits: pin1,
            expectedChipSerial: expectedChipSerial
          )
        }
      return answer ?? .failure(.noCard)
    }

    /// Reads the qualified signing certificate and its advertised Web eID
    /// signature algorithms after the holder grants consent.
    internal static func executeGetSigningCertificate(
      expectedChipSerial: ChipSerial
    ) async -> Result<WebEidResponsePayload, WebEidCardFailure> {
      let answer: Result<WebEidResponsePayload, WebEidCardFailure>? =
        await CardMaintenance.onReader { operations in
          getSigningCertificateInSession(
            operations,
            expectedChipSerial: expectedChipSerial
          )
        }
      return answer ?? .failure(.noCard)
    }

    /// Verifies PIN 2, signs the pre-computed document digest, and locally
    /// verifies the resulting raw signature before returning it to Safari.
    internal static func executeSign(
      request: WebEidCommand.SignRequest,
      pin2: String,
      expectedChipSerial: ChipSerial
    ) async -> Result<WebEidResponsePayload, WebEidCardFailure> {
      guard Pin2(digits: pin2) != nil else {
        return .failure(.invalidPinEntry)
      }
      let answer: Result<WebEidResponsePayload, WebEidCardFailure>? =
        await CardMaintenance.onReader { operations in
          signInSession(
            operations,
            request: request,
            pinDigits: pin2,
            expectedChipSerial: expectedChipSerial
          )
        }
      return answer ?? .failure(.noCard)
    }

    private static func authenticateInSession(
      _ operations: CardOperations,
      origin: WebEidOrigin,
      challengeNonce: String,
      pinDigits: String,
      expectedChipSerial: ChipSerial
    ) -> Result<WebEidResponsePayload, WebEidCardFailure> {
      guard let pin = Pin1(digits: pinDigits) else {
        return .failure(.invalidPinEntry)
      }
      guard let serial = try? operations.readChipSerial(), serial == expectedChipSerial else {
        return .failure(.certificateMismatch)
      }
      guard let resolved = readResolvedCertificate(operations, signing: false) else {
        return .failure(.certificateUnavailable)
      }
      if let floorFailure = checkRetryFloor(operations, role: .pin1) {
        return .failure(floorFailure)
      }
      let params = WebEidCrypto.authParameters(for: resolved.profile)
      guard
        let digest = WebEidCrypto.authenticationDigest(
          origin: origin,
          challengeNonce: challengeNonce,
          hashFunction: params.hashFunction
        )
      else {
        return .failure(.unsupportedAlgorithm)
      }
      return performAuthentication(
        operations,
        resolved: resolved,
        digest: digest,
        params: params,
        pin: pin
      )
    }

    private static func performAuthentication(
      _ operations: CardOperations,
      resolved: ResolvedCertificate,
      digest: Data,
      params: WebEidCrypto.AuthParameters,
      pin: consuming Pin1
    ) -> Result<WebEidResponsePayload, WebEidCardFailure> {
      do {
        try operations.verifyPin1(pin.consumeForSingleTransmission())
        let rawSignature = try operations.computeAuthenticationSignature(
          overDigest: digest,
          algorithm: params.cardAlgorithm,
          expectedSignatureLength: resolved.profile.expectedSignatureLength
        )
        guard
          WebEidCrypto.verifyRawSignature(
            rawSignature,
            overDigest: digest,
            hashFunction: params.hashFunction,
            profile: resolved.profile,
            publicKey: resolved.publicKey
          )
        else {
          return .failure(.cardError)
        }
        return .success(
          WebEidCrypto.makeAuthenticationResponse(
            certificateDER: resolved.der,
            jwsAlgorithm: params.jwsAlgorithm,
            rawSignature: rawSignature,
            appVersion: currentAppVersion()
          )
        )
      } catch {
        return .failure(mapCardError(error, operations: operations))
      }
    }

    private static func getSigningCertificateInSession(
      _ operations: CardOperations,
      expectedChipSerial: ChipSerial
    ) -> Result<WebEidResponsePayload, WebEidCardFailure> {
      guard let serial = try? operations.readChipSerial(), serial == expectedChipSerial else {
        return .failure(.certificateMismatch)
      }
      guard let resolved = readResolvedCertificate(operations, signing: true) else {
        return .failure(.certificateUnavailable)
      }
      return .success(
        .getSigningCertificate(
          certificate: resolved.der.base64EncodedString(),
          supportedSignatureAlgorithms: WebEidCrypto.supportedSigningAlgorithms(
            for: resolved.profile
          )
        )
      )
    }

    private static func signInSession(
      _ operations: CardOperations,
      request: WebEidCommand.SignRequest,
      pinDigits: String,
      expectedChipSerial: ChipSerial
    ) -> Result<WebEidResponsePayload, WebEidCardFailure> {
      guard let pin = Pin2(digits: pinDigits) else {
        return .failure(.invalidPinEntry)
      }
      guard let serial = try? operations.readChipSerial(), serial == expectedChipSerial else {
        return .failure(.certificateMismatch)
      }
      guard let resolved = readResolvedCertificate(operations, signing: true) else {
        return .failure(.certificateUnavailable)
      }
      guard resolved.der == request.certificateDER else {
        return .failure(.certificateMismatch)
      }
      guard (try? operations.requiresPin2ChangeBeforeSigning()) != true else {
        Task { @MainActor in
          CredentialRetryHealth.shared.markPin2RequiresChangeBeforeSigning()
        }
        return .failure(.pin2RequiresChangeBeforeSigning)
      }
      if let floorFailure = checkRetryFloor(operations, role: .pin2) {
        return .failure(floorFailure)
      }
      return performQualifiedSign(
        operations,
        resolved: resolved,
        request: request,
        pin: pin
      )
    }

    private static func performQualifiedSign(
      _ operations: CardOperations,
      resolved: ResolvedCertificate,
      request: WebEidCommand.SignRequest,
      pin: consuming Pin2
    ) -> Result<WebEidResponsePayload, WebEidCardFailure> {
      let supportedHashes = WebEidCrypto.supportedSigningAlgorithms(for: resolved.profile)
        .map(\.hashFunction)
      guard supportedHashes.contains(request.hashFunction.rawValue) else {
        return .failure(.unsupportedAlgorithm)
      }
      let parameters = WebEidCrypto.signingParameters(
        for: resolved.profile,
        hashFunction: request.hashFunction
      )
      do {
        if (try? operations.resolveCredentialReferences()) == .organization {
          try operations.selectEsignDirectory()
        }
        try operations.verifyPin2(pin.consumeForSingleTransmission())
        let rawSignature = try operations.computeQualifiedSignature(
          overDigest: request.hash,
          algorithm: parameters.cardAlgorithm,
          expectedSignatureLength: resolved.profile.expectedSignatureLength
        )
        guard
          WebEidCrypto.verifyRawSignature(
            rawSignature,
            overDigest: request.hash,
            hashFunction: request.hashFunction,
            profile: resolved.profile,
            publicKey: resolved.publicKey
          )
        else {
          return .failure(.cardError)
        }
        return .success(
          .sign(
            signature: rawSignature.base64EncodedString(),
            signatureAlgorithm: parameters.wireAlgorithm
          )
        )
      } catch {
        return .failure(mapCardError(error, operations: operations))
      }
    }
  }

#endif
