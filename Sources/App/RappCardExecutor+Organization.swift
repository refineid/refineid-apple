// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation
  import os
  import Security

  /// A signature by the phone's organization card for a paired computer.
  ///
  /// The card opens only with PACE and the PIN the operation spends
  /// (FINEID S1 v4.0, organizational cards, section 2.1), so every
  /// signature runs its own PACE on the field's plain channel. The retry
  /// floor and the held PIN 1 rule decide on the state MSE:Set AT reports,
  /// before the card takes a try (``OrganizationCardOpening``); the
  /// completed PACE counts as the PIN verified, so no VERIFY is sent. The
  /// certificates come from the prime, and every signature is checked
  /// against them before it is returned.
  extension RappCardExecutor {
    /// The operation on an organization card: PACE with `params.pin`, the
    /// key's directory made current, the signature.
    internal static func executeOrganizationSign(
      _ params: SignParameters,
      on plain: CardOperations,
      context: RappNearFieldSessionHolder.Context,
      observer: Pin1ProbeObserver?
    ) -> Outcome {
      guard OrganizationCardSupport.isEnabled else {
        return .refusedBeforeCredentialTransmit(.cardUnavailable)
      }
      guard case .organization(let prime)? = PhoneCardPrime.current else {
        return .refusedBeforeCredentialTransmit(.cardUnavailable)
      }
      let fingerprint = params.pin.sessionFingerprint
      if context.isNegativePin(fingerprint) {
        observer?.clearHeld()
        return .refusedBeforeCredentialTransmit(.invalidCredential(params.role))
      }
      let didRecordProbe = OSAllocatedUnfairLock(initialState: false)
      let noteProbe: @Sendable (RetryProbeOutcome) -> Void = { probe in
        didRecordProbe.withLock { $0 = true }
        observer?.recordProbe(probe)
      }
      let opened: OrganizationCardOpening.Opened
      do {
        opened = try Self.opened(plain, pin: params.pin, recordProbe: noteProbe)
      } catch {
        let outcome = Self.refusal(
          error,
          params: params,
          context: context,
          observer: observer,
          recordProbe: noteProbe
        )
        if outcome == .completionAmbiguous, !didRecordProbe.withLock({ $0 }) {
          observer?.recordProbe(.noInformation)
        }
        return outcome
      }
      let operations = opened.operations
      if params.qualified {
        return signQualifiedOrganization(params, operations: operations)
      }
      guard (try? operations.readChipSerial()) == prime.chipSerial,
        let identity = identity(params: params, operations: operations, allowCache: true)
      else {
        observer?.clearHeld()
        return .refusedBeforeCredentialTransmit(.keyOrAlgorithmMismatch)
      }
      observer?.recordCard(identity.certificateDER)
      return computeAndVerifySignature(operations: operations, identity: identity, qualified: false)
    }

    private static func signQualifiedOrganization(
      _ params: SignParameters,
      operations: CardOperations
    ) -> Outcome {
      guard
        let identity = identity(params: params, operations: operations, allowCache: true),
        (try? operations.selectEsignDirectory()) != nil
      else {
        return .completionAmbiguous
      }
      return computeAndVerifySignature(operations: operations, identity: identity, qualified: true)
    }

    /// PACE with the operation's PIN, one single-use PIN from its entry.
    private static func opened(
      _ plain: CardOperations,
      pin: SigningPin,
      recordProbe: (@Sendable (RetryProbeOutcome) -> Void)?
    ) throws -> OrganizationCardOpening.Opened {
      switch pin {
      case .enteredPin1(let entry):
        try OrganizationCardOpening.pin1(
          over: plain,
          entry.issue().consumeForSingleTransmission(),
          spending: .entered,
          onPinState: recordProbe
        )

      case .heldPin1(let entry):
        try OrganizationCardOpening.pin1(
          over: plain,
          entry.issue().consumeForSingleTransmission(),
          spending: .heldPin1,
          onPinState: recordProbe
        )

      case .pin2(let entry):
        try OrganizationCardOpening.pin2(
          over: plain, entry.issue().consumeForSingleTransmission())
      }
    }

    /// The outcome a refused handshake comes to.
    ///
    /// Every refusal before GENERAL AUTHENTICATE sent the card no try; a
    /// wrong PIN is remembered for the session so it is never sent again.
    private static func refusal(
      _ error: any Error,
      params: SignParameters,
      context: RappNearFieldSessionHolder.Context,
      observer: Pin1ProbeObserver?,
      recordProbe: (@Sendable (RetryProbeOutcome) -> Void)?
    ) -> Outcome {
      let role = params.role
      switch error {
      case PaceEstablishment.Failure.credentialBlocked:
        recordProbe?(.locked)
        return .refusedBeforeCredentialTransmit(.credentialBlocked(role))

      case PaceEstablishment.Failure.retryFloorRefused(let verdict, let state):
        recordProbe?(state)
        return .refusedBeforeCredentialTransmit(.retryFloor(role, verdict))

      case PaceEstablishment.Failure.heldPinUnconfirmed(let state):
        recordProbe?(state)
        return .refusedBeforeCredentialTransmit(.heldPin1Unconfirmed)

      case PaceEstablishment.Failure.passwordDeactivated:
        recordProbe?(.invalidated)
        return .refusedBeforeCredentialTransmit(.credentialInvalidated(role))

      case PaceEstablishment.Failure.wrongPin(let remaining):
        context.recordNegativePin(params.pin.sessionFingerprint, role)
        if role == .pin1 {
          observer?.clearHeld()
        }
        return .rejected(.credential(role, remaining: remaining.isBlocked ? nil : remaining))

      case PaceEstablishment.Failure.cardAccessUnreadable,
        PaceEstablishment.Failure.cardAccessMalformed,
        PaceEstablishment.Failure.noSupportedSuite:
        return .refusedBeforeCredentialTransmit(.cardUnavailable)

      default:
        return .completionAmbiguous
      }
    }
  }

  extension RappCardExecutor.SigningPin {
    /// The entry's fingerprint for the session's rejected-PIN memory.
    internal var sessionFingerprint: PinFingerprint {
      switch self {
      case .enteredPin1(let entry), .heldPin1(let entry):
        entry.sessionFingerprint()

      case .pin2(let entry):
        entry.sessionFingerprint()
      }
    }
  }
#endif
