// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation
  import Security

  extension RappCardExecutor {
    internal static func browserAuthentication(
      cardAccessNumber: String?,
      pin1: SigningPin,
      keyProfile: RappOperationDriver.KeyProfile,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      digest: Data
    ) async -> BrowserAuthenticationOutcome {
      let observer = Pin1ProbeObserver()
      let outcome = await sign(
        SignParameters(
          cardAccessNumber: cardAccessNumber,
          pin: pin1,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: digest
        ),
        observer: observer
      )
      return BrowserAuthenticationOutcome(
        outcome: outcome,
        preVerifyProbe: observer.preVerifyProbe,
        authenticatedCard: observer.authenticatedCard
      )
    }

    internal static func signDocument(
      cardAccessNumber: String?,
      pin2: Pin2Entry,
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
        ),
        observer: nil
      )
    }

    private static func sign(
      _ params: SignParameters,
      observer: Pin1ProbeObserver?
    ) async -> Outcome {
      await withCard(
        cardAccessNumber: params.cardAccessNumber,
        operation: params.qualified ? .signature : .authentication,
        organization: { plain, context in
          executeOrganizationSign(params, on: plain, context: context, observer: observer)
        },
        personal: { operations, context in
          executeSign(params, with: operations, context: context, observer: observer)
        }
      )
    }

    internal static func executeSign(
      _ params: SignParameters,
      with operations: CardOperations,
      context: RappNearFieldSessionHolder.Context?,
      observer: Pin1ProbeObserver?
    ) -> Outcome {
      guard
        let identity = identity(
          params: params,
          operations: operations,
          allowCache: context != nil
        )
      else {
        observer?.clearHeld()
        return .refusedBeforeCredentialTransmit(.keyOrAlgorithmMismatch)
      }
      observer?.recordCard(identity.certificateDER)

      // The counter is read once per card session when the session already
      // recorded a verified state in CardOperations; an entered PIN 1 on an
      // uncached session still reads the card's counter before VERIFY.
      if context?.isRoleProbed(params.role) != true
        || operations.probedRetryCounter(role: params.role) == nil
      {
        let evaluation = evaluateRetryFloor(operations: operations, pin: params.pin)
        observer?.recordProbe(evaluation.probe)
        if let refusal = evaluation.refusal {
          return .refusedBeforeCredentialTransmit(refusal)
        }
      } else if let cached = operations.probedRetryCounter(role: params.role) {
        observer?.recordProbe(cached)
      }

      if let verificationOutcome = verifyCredential(
        params.pin,
        operations: operations,
        context: context
      ) {
        if params.role == .pin1, case .rejected = verificationOutcome {
          observer?.clearHeld()
        }
        return verificationOutcome
      }
      context?.markRoleProbed(params.role)

      return computeAndVerifySignature(
        operations: operations,
        identity: identity,
        qualified: params.qualified
      )
    }

    /// The pre-VERIFY counter reading and why it forbids spending `pin`, or
    /// nil refusal when it allows it (``PinAdmission``).
    private static func evaluateRetryFloor(
      operations: CardOperations,
      pin: SigningPin
    ) -> (probe: RetryProbeOutcome, refusal: Refusal?) {
      let role = pin.role
      let probe: RetryProbeOutcome
      do {
        probe = try operations.probeRetryCounter(role: role)
      } catch {
        return (.noInformation, .retryFloor(role, .refuseUnreadable))
      }
      switch PinAdmission(probe: probe, spending: pin.spending) {
      case .proceed:
        return (probe, nil)

      case .credentialBlocked:
        return (probe, .credentialBlocked(role))

      case .credentialInvalidated:
        return (probe, .credentialInvalidated(role))

      case .retryFloor(let verdict):
        return (probe, .retryFloor(role, verdict))

      case .heldPin1Unconfirmed:
        return (probe, .heldPin1Unconfirmed)
      }
    }

    private static func verifyCredential(
      _ pin: SigningPin,
      operations: CardOperations,
      context: RappNearFieldSessionHolder.Context?
    ) -> Outcome? {
      switch pin {
      case .enteredPin1(let entry), .heldPin1(let entry):
        verifyRolePin1(entry, operations: operations, context: context)

      case .pin2(let entry):
        verifyRolePin2(entry, operations: operations, context: context)
      }
    }

    /// Verifies PIN 1 for this operation.
    ///
    /// The card keeps no verified state from one signature to the next on
    /// a held channel: a PSO sent without a fresh VERIFY is refused with
    /// security status not satisfied.
    private static func verifyRolePin1(
      _ entry: Pin1Entry,
      operations: CardOperations,
      context: RappNearFieldSessionHolder.Context?
    ) -> Outcome? {
      let fingerprint = entry.sessionFingerprint()
      if let context, context.isNegativePin(fingerprint) {
        return .refusedBeforeCredentialTransmit(.invalidCredential(.pin1))
      }
      let outcome = verifyPin1(entry.issue(), with: operations)
      if outcome == nil {
        OperationPhaseTrace.mark("credential-verified")
      } else if case .rejected = outcome {
        context?.recordNegativePin(fingerprint, .pin1)
      }
      return outcome
    }

    private static func verifyRolePin2(
      _ entry: Pin2Entry,
      operations: CardOperations,
      context: RappNearFieldSessionHolder.Context?
    ) -> Outcome? {
      let fingerprint = entry.sessionFingerprint()
      if let context, context.isNegativePin(fingerprint) {
        return .refusedBeforeCredentialTransmit(.invalidCredential(.pin2))
      }
      let outcome = verifyPin2(entry.issue(), with: operations)
      if case .rejected = outcome {
        context?.recordNegativePin(fingerprint, .pin2)
      }
      return outcome
    }

    internal static func computeAndVerifySignature(
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
        // raw value (RAPP v26.11.8 §9.2).
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

    /// The certificate an organization card's prime holds for `slot`.
    private static func organizationCertificate(
      _ prime: OrganizationPrime,
      slot: CertificateSlot
    ) -> Data? {
      switch slot {
      case .authentication:
        prime.certificateDER

      case .qualifiedSignature:
        prime.signatureCertificateDER

      default:
        nil
      }
    }

    internal static func identity(
      params: SignParameters,
      operations: CardOperations,
      allowCache: Bool
    ) -> Identity? {
      let cachedCertData: Data? = {
        guard allowCache else { return nil }
        if OrganizationCardStore.kind() == .organization {
          guard case .organization(let prime)? = PhoneCardPrime.current else { return nil }
          return organizationCertificate(prime, slot: params.slot)
        }
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
      return Identity(
        certificateDER: certificateData, publicKey: publicKey, request: request)
    }
  }
#endif
