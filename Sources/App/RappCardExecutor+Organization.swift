// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation
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
      context: RappNearFieldSessionHolder.Context
    ) -> Outcome {
      guard case .organization(let prime)? = PhoneCardPrime.current else {
        return .refusedBeforeCredentialTransmit(.cardUnavailable)
      }
      let fingerprint = params.pin.sessionFingerprint
      if context.isNegativePin(fingerprint) {
        return .refusedBeforeCredentialTransmit(.invalidCredential(params.role))
      }
      let opened: OrganizationCardOpening.Opened
      do {
        opened = try Self.opened(plain, pin: params.pin)
      } catch {
        return Self.refusal(error, params: params, fingerprint: fingerprint, context: context)
      }
      let operations = opened.operations
      if params.qualified {
        guard
          let identity = identity(params: params, operations: operations, allowCache: true),
          (try? operations.selectEsignDirectory()) != nil
        else {
          return .completionAmbiguous
        }
        return computeAndVerifySignature(
          operations: operations, identity: identity, qualified: true)
      }
      guard (try? operations.readChipSerial()) == prime.chipSerial else {
        return .refusedBeforeCredentialTransmit(.keyOrAlgorithmMismatch)
      }
      guard let identity = identity(params: params, operations: operations, allowCache: true)
      else {
        return .refusedBeforeCredentialTransmit(.keyOrAlgorithmMismatch)
      }
      return computeAndVerifySignature(operations: operations, identity: identity, qualified: false)
    }

    /// PACE with the operation's PIN, one single-use PIN from its entry.
    private static func opened(
      _ plain: CardOperations,
      pin: SigningPin
    ) throws -> OrganizationCardOpening.Opened {
      switch pin {
      case .enteredPin1(let entry):
        try OrganizationCardOpening.pin1(
          over: plain, entry.issue().consumeForSingleTransmission(), spending: .entered)

      case .heldPin1(let entry):
        try OrganizationCardOpening.pin1(
          over: plain, entry.issue().consumeForSingleTransmission(), spending: .heldPin1)

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
      fingerprint: PinFingerprint,
      context: RappNearFieldSessionHolder.Context
    ) -> Outcome {
      let role = params.role
      switch error {
      case PaceEstablishment.Failure.retryFloorRefused(_, .locked):
        return .refusedBeforeCredentialTransmit(.credentialBlocked(role))

      case PaceEstablishment.Failure.retryFloorRefused(let verdict, _):
        return .refusedBeforeCredentialTransmit(.retryFloor(role, verdict))

      case PaceEstablishment.Failure.heldPinUnconfirmed:
        return .refusedBeforeCredentialTransmit(.heldPin1Unconfirmed)

      case PaceEstablishment.Failure.passwordDeactivated:
        return .refusedBeforeCredentialTransmit(.credentialInvalidated(role))

      case PaceEstablishment.Failure.wrongPin(let remaining):
        context.recordNegativePin(fingerprint, role)
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
