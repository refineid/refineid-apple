// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation
  import Security

  extension RappCardExecutor {
    /// The PIN a signature spends (RAPP v26.10.29 §8.2 item 3, §11 item 2).
    internal enum SigningPin: Sendable, Equatable {
      /// PIN 1 the holder typed for this browser authentication.
      case enteredPin1(String)
      /// PIN 1 held from an earlier operation the card accepted; spent only
      /// while the card's PIN 1 counter shows no refusal since.
      case heldPin1(String)
      /// PIN 2 the holder typed for this signature or batch.
      case pin2(String)

      /// The credential the card checks it as.
      internal var role: CredentialRole {
        switch self {
        case .enteredPin1, .heldPin1:
          .pin1

        case .pin2:
          .pin2
        }
      }

      /// Where the PIN comes from, for the counter check before it is sent.
      internal var spending: PinAdmission.Spending {
        switch self {
        case .heldPin1:
          .heldPin1

        case .enteredPin1, .pin2:
          .entered
        }
      }

      /// The digits the card is sent.
      internal var digits: String {
        switch self {
        case .enteredPin1(let digits), .heldPin1(let digits), .pin2(let digits):
          digits
        }
      }
    }

    internal struct SignParameters {
      internal let cardAccessNumber: String?
      internal let pin: SigningPin
      internal let keyProfile: RappOperationDriver.KeyProfile
      internal let algorithm: RappOperationDriver.SignatureAlgorithm
      internal let digest: Data

      internal var role: CredentialRole { pin.role }

      /// Whether this is a qualified signature, with PIN 2.
      internal var qualified: Bool { pin.role == .pin2 }

      /// The certificate whose key signs.
      internal var slot: CertificateSlot { qualified ? .qualifiedSignature : .authentication }
    }

    internal static func browserAuthentication(
      cardAccessNumber: String?,
      pin1: SigningPin,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digest: Data
    ) async -> Outcome {
      await sign(
        SignParameters(
          cardAccessNumber: cardAccessNumber,
          pin: pin1,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: digest
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
          pin: .pin2(pin2),
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: digest
        )
      )
    }

    private static func sign(
      _ params: SignParameters
    ) async -> Outcome {
      await withCard(
        cardAccessNumber: params.cardAccessNumber,
        operation: params.qualified ? .signature : .authentication
      ) { operations, context in
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

      // The counter is read once per card session: a session that ended
      // without the card answering opens a new one, and the next use reads
      // it again (RAPP v26.10.29 §11 item 2).
      if context?.isRoleProbed(params.role) != true {
        if let refusal = evaluateRetryFloor(operations: operations, pin: params.pin) {
          return .refusedBeforeCredentialTransmit(refusal)
        }
        context?.markRoleProbed(params.role)
      }

      if let verificationOutcome = verifyCredential(
        params.pin,
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

    /// Why the card's counter forbids spending `pin`, or nil when it
    /// allows it (``PinAdmission``).
    private static func evaluateRetryFloor(
      operations: CardOperations,
      pin: SigningPin
    ) -> Refusal? {
      let role = pin.role
      let probe: RetryProbeOutcome
      do {
        probe = try operations.probeRetryCounter(role: role)
      } catch {
        return .retryFloor(role, .refuseUnreadable)
      }
      switch PinAdmission(probe: probe, spending: pin.spending) {
      case .proceed:
        return nil

      case .credentialBlocked:
        return .credentialBlocked(role)

      case .credentialInvalidated:
        return .credentialInvalidated(role)

      case .retryFloor(let verdict):
        return .retryFloor(role, verdict)

      case .heldPin1Unconfirmed:
        return .heldPin1Unconfirmed
      }
    }

    private static func verifyCredential(
      _ pin: SigningPin,
      operations: CardOperations,
      context: RappNearFieldSessionHolder.Context?
    ) -> Outcome? {
      switch pin {
      case .enteredPin1(let digits), .heldPin1(let digits):
        verifyRolePin1(digits, operations: operations, context: context)

      case .pin2(let digits):
        verifyRolePin2(digits, operations: operations, context: context)
      }
    }

    /// Verifies PIN 1 for this operation.
    ///
    /// The card keeps no verified state from one signature to the next on
    /// a held channel: a PSO sent without a fresh VERIFY is refused with
    /// security status not satisfied.
    private static func verifyRolePin1(
      _ rawDigits: String,
      operations: CardOperations,
      context: RappNearFieldSessionHolder.Context?
    ) -> Outcome? {
      guard let pin = Pin1(digits: rawDigits) else {
        return .refusedBeforeCredentialTransmit(.invalidCredential(.pin1))
      }
      if let context, context.isNegativePin(rawDigits) {
        return .refusedBeforeCredentialTransmit(.invalidCredential(.pin1))
      }
      let outcome = verifyPin1(pin, with: operations)
      if outcome == nil {
        OperationPhaseTrace.mark("credential-verified")
      } else if case .rejected = outcome {
        context?.recordNegativePin(rawDigits, .pin1)
      }
      return outcome
    }

    private static func verifyRolePin2(
      _ documentPin2: String,
      operations: CardOperations,
      context: RappNearFieldSessionHolder.Context?
    ) -> Outcome? {
      guard let pin = Pin2(digits: documentPin2) else {
        return .refusedBeforeCredentialTransmit(.invalidCredential(.pin2))
      }
      if let context, context.isNegativePin(documentPin2) {
        return .refusedBeforeCredentialTransmit(.invalidCredential(.pin2))
      }
      let outcome = verifyPin2(pin, with: operations)
      if case .rejected = outcome {
        context?.recordNegativePin(documentPin2, .pin2)
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
        // raw value (RAPP v26.10.29 §9.2).
        guard
          let verifiable = identity.request.wireSignature(from: raw),
          identity.request.isSatisfied(by: verifiable, from: identity.publicKey)
        else {
          return .completionAmbiguous
        }
        OperationPhaseTrace.mark("signature-done")
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
          return params.cardAccessNumber.flatMap { accessNumber in
            PrimeStore.signatureCertificate(cardAccessNumber: accessNumber)
          }
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
      if allowCache, cachedCertData == nil, let readFromCard,
        params.slot == .qualifiedSignature, let accessNumber = params.cardAccessNumber
      {
        PrimeStore.updateSignatureCertificate(readFromCard, cardAccessNumber: accessNumber)
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
