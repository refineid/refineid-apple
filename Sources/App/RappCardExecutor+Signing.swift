// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation
  import Security

  extension RappCardExecutor {
    internal struct SignParameters {
      internal let cardAccessNumber: String?
      internal let documentPin1: String?
      internal let documentPin2: String?
      internal let role: CredentialRole
      internal let slot: CertificateSlot
      internal let keyProfile: RappOperationDriver.KeyProfile
      internal let algorithm: RappOperationDriver.SignatureAlgorithm
      internal let digest: Data
      internal let qualified: Bool
    }

    internal static func browserAuthentication(
      cardAccessNumber: String?,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digest: Data
    ) async -> Outcome {
      await browserAuthentication(
        cardAccessNumber: cardAccessNumber,
        pin1: nil,
        keyProfile: keyProfile,
        algorithm: algorithm,
        digest: digest
      )
    }

    internal static func browserAuthentication(
      cardAccessNumber: String?,
      pin1: String?,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digest: Data
    ) async -> Outcome {
      await sign(
        SignParameters(
          cardAccessNumber: cardAccessNumber,
          documentPin1: pin1,
          documentPin2: nil,
          role: .pin1,
          slot: .authentication,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: digest,
          qualified: false
        )
      )
    }

    internal static func signDocument(
      cardAccessNumber: String?,
      pin2: String,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digest: Data
    ) async -> Outcome {
      await sign(
        SignParameters(
          cardAccessNumber: cardAccessNumber,
          documentPin1: nil,
          documentPin2: pin2,
          role: .pin2,
          slot: .qualifiedSignature,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: digest,
          qualified: true
        )
      )
    }

    private static func sign(
      _ params: SignParameters
    ) async -> Outcome {
      await withCard(cardAccessNumber: params.cardAccessNumber) { operations, context in
        executeSign(params, with: operations, context: context)
      }
    }

    internal static func executeSign(
      _ params: SignParameters,
      with operations: CardOperations,
      context: RappNearFieldSessionHolder.Context?
    ) -> Outcome {
      guard
        let identity = identity(
          params: params,
          operations: operations,
          allowCache: context != nil
        )
      else {
        return .refusedBeforeCredentialTransmit(.keyOrAlgorithmMismatch)
      }

      if let context, !context.isRoleProbed(params.role) {
        if let floorRefusal = evaluateRetryFloor(operations: operations, role: params.role) {
          return .refusedBeforeCredentialTransmit(floorRefusal)
        }
        context.markRoleProbed(params.role)
      } else if context == nil {
        if let floorRefusal = evaluateRetryFloor(operations: operations, role: params.role) {
          return .refusedBeforeCredentialTransmit(floorRefusal)
        }
      }

      if let verificationOutcome = verifyCredential(
        role: params.role,
        documentPin1: params.documentPin1,
        documentPin2: params.documentPin2,
        operations: operations,
        context: context
      ) {
        return verificationOutcome
      }

      return computeAndVerifySignature(
        operations: operations,
        identity: identity,
        qualified: params.qualified
      )
    }

    private static func evaluateRetryFloor(
      operations: CardOperations,
      role: CredentialRole
    ) -> Refusal? {
      let probe: RetryProbeOutcome
      do {
        probe = try operations.probeRetryCounter(role: role)
      } catch {
        return .retryFloor(role, .refuseUnreadable)
      }
      switch probe {
      case .locked:
        return .credentialBlocked(role)

      case .invalidated:
        return .credentialInvalidated(role)

      case .remaining, .verified:
        let verdict = RetryFloor.evaluate(probeOutcome: probe)
        return verdict == .proceed ? nil : .retryFloor(role, verdict)

      case .noInformation, .other:
        return .retryFloor(role, .refuseUnreadable)
      }
    }

    private static func verifyCredential(
      role: CredentialRole,
      documentPin1: String?,
      documentPin2: String?,
      operations: CardOperations,
      context: RappNearFieldSessionHolder.Context?
    ) -> Outcome? {
      switch role {
      case .pin1:
        verifyRolePin1(documentPin1: documentPin1, operations: operations, context: context)

      case .pin2:
        verifyRolePin2(documentPin2: documentPin2, operations: operations, context: context)

      case .puk:
        .refusedBeforeCredentialTransmit(.invalidCredential(role))
      }
    }

    private static func verifyRolePin1(
      documentPin1: String?,
      operations: CardOperations,
      context: RappNearFieldSessionHolder.Context?
    ) -> Outcome? {
      if let context, context.isPin1Authenticated {
        return nil
      }
      let pin: Pin1?
      let rawDigits: String?
      if let documentPin1 {
        pin = Pin1(digits: documentPin1)
        rawDigits = documentPin1
      } else {
        pin = CardCredentialStore.pin1()
        rawDigits = CardCredentialStore.pin1Digits()
      }
      guard let pin, let rawDigits else {
        return .refusedBeforeCredentialTransmit(.invalidCredential(.pin1))
      }
      if let context, context.isNegativePin(rawDigits) {
        return .refusedBeforeCredentialTransmit(.invalidCredential(.pin1))
      }
      let outcome = verifyPin1(pin, with: operations)
      if outcome == nil {
        context?.markPin1Authenticated()
      } else if case .rejected = outcome {
        context?.recordNegativePin(rawDigits)
      }
      return outcome
    }

    private static func verifyRolePin2(
      documentPin2: String?,
      operations: CardOperations,
      context: RappNearFieldSessionHolder.Context?
    ) -> Outcome? {
      guard
        let documentPin2,
        let pin = Pin2(digits: documentPin2)
      else {
        return .refusedBeforeCredentialTransmit(.invalidCredential(.pin2))
      }
      if let context, context.isNegativePin(documentPin2) {
        return .refusedBeforeCredentialTransmit(.invalidCredential(.pin2))
      }
      let outcome = verifyPin2(pin, with: operations)
      if case .rejected = outcome {
        context?.recordNegativePin(documentPin2)
      }
      return outcome
    }

    private static func computeAndVerifySignature(
      operations: CardOperations,
      identity: Identity,
      qualified: Bool
    ) -> Outcome {
      do {
        let raw =
          try qualified
          ? operations.computeQualifiedSignature(
            overDigest: identity.request.digest,
            algorithm: identity.request.algorithm,
            expectedSignatureLength: identity.request.expectedSignatureLength
          )
          : operations.computeAuthenticationSignature(
            overDigest: identity.request.digest,
            algorithm: identity.request.algorithm,
            expectedSignatureLength: identity.request.expectedSignatureLength
          )
        // Verified locally in its DER form; the wire carries the card's
        // raw value (RAPP v26.10.9 section 9.2).
        guard
          let verifiable = identity.request.wireSignature(from: raw),
          identity.request.isSatisfied(by: verifiable, from: identity.publicKey)
        else {
          return .completionAmbiguous
        }
        return .result(raw)
      } catch {
        return .completionAmbiguous
      }
    }

    /// Nil means VERIFY succeeded.
    ///
    /// Every other value is terminal for this operation and no caller
    /// may automatically resend the PIN.
    private static func verifyPin1(
      _ pin: consuming Pin1,
      with operations: CardOperations
    ) -> Outcome? {
      do {
        try operations.verifyPin1(pin.consumeForSingleTransmission())
        return nil
      } catch CardOperationError.pinRejected(let remaining) {
        return .rejected(.credential(.pin1, remaining: remaining))
      } catch CardOperationError.pinBlocked {
        return .rejected(.credential(.pin1, remaining: nil))
      } catch CardOperationError.credentialInvalidated {
        return .rejected(.credential(.pin1, remaining: nil))
      } catch {
        return .completionAmbiguous
      }
    }

    /// PIN2 sibling of `verifyPin1`; kept separate so the type system cannot
    /// route one role's credential into the other role's command.
    private static func verifyPin2(
      _ pin: consuming Pin2,
      with operations: CardOperations
    ) -> Outcome? {
      do {
        try operations.verifyPin2(pin.consumeForSingleTransmission())
        return nil
      } catch CardOperationError.pinRejected(let remaining) {
        return .rejected(.credential(.pin2, remaining: remaining))
      } catch CardOperationError.pinBlocked {
        return .rejected(.credential(.pin2, remaining: nil))
      } catch CardOperationError.credentialInvalidated {
        return .rejected(.credential(.pin2, remaining: nil))
      } catch {
        return .completionAmbiguous
      }
    }

    private static func identity(
      params: SignParameters,
      operations: CardOperations,
      allowCache: Bool
    ) -> Identity? {
      let cachedCertData: Data? = {
        guard allowCache else { return nil }
        let stored = PrimeStore.storedIdentities().first
        switch params.slot {
        case .authentication:
          return stored?.certDER
        case .qualifiedSignature:
          return stored?.signatureCertDER
        default:
          return nil
        }
      }()
      let readFromCard: Data? = {
        guard cachedCertData == nil else { return nil }
        return (try? operations.readCertificate(params.slot))
          ?? (try? operations.readCertificate(
            params.slot == .qualifiedSignature
              ? .secondQualifiedSignature : .secondAuthentication
          ))
      }()
      if cachedCertData == nil, let readFromCard, params.slot == .qualifiedSignature {
        PrimeStore.updateSignatureCertificate(readFromCard)
      }
      guard
        let certificateData = cachedCertData ?? readFromCard,
        let certificate = SecCertificateCreateWithData(
          nil, certificateData as CFData
        ),
        let publicKey = SecCertificateCopyKey(certificate),
        CardKeyProfile.resolve(fromPublicKey: publicKey) == params.keyProfile.cardKeyProfile,
        let request = SignRequest.resolve(
          profile: params.keyProfile.cardKeyProfile,
          algorithm: params.algorithm.signingAlgorithm,
          digest: params.digest
        )
      else {
        return nil
      }
      return Identity(publicKey: publicKey, request: request)
    }
  }
#endif
