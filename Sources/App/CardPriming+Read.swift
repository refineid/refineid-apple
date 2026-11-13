// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import CardCore
  import Foundation

  /// The card I/O of a first prime: the card's kind, PACE and the reads,
  /// inside the one field's exclusive card session.
  extension CardPriming {
    /// Stores a personal card's identity with the access number its PACE
    /// proved.
    internal typealias StorePersonalIdentity = (Identity, ProvenAccessNumber) throws -> Void

    /// Reads everything the later signature must not have to read.
    ///
    /// Runs on the card queue inside the field's exclusive session. The
    /// entry's selected kind controls which credential opens PACE; a card
    /// refusal cannot reinterpret a CAN as PIN 1 or a PIN 1 as CAN.
    /// `store` receives a personal card's identity as soon as it is read
    /// and checked, so the token extension's mint, already waiting in this
    /// field, finds the prime while the hold reads the counters and any
    /// root.
    internal static func read(
      _ execution: HoldExecution,
      store: @escaping StorePersonalIdentity
    ) throws -> HoldRead {
      let sheet = execution.sheet
      let isRecovery = execution.isRecovery
      let waitBudget = Self.responseWait(for: execution.entry.kind, isRecovery: isRecovery)
      return try execution.session.withCardSession(waits: waitBudget) { channel in
        switch execution.entry.kind {
        case .personal:
          guard let proven = execution.entry.personalAccessNumber() else {
            throw Failure.wrongCardAccessNumber
          }
          return try Self.readPersonal(
            channel: channel, proven: proven, sheet: sheet,
            isRecovery: isRecovery, store: store)

        case .organization:
          guard let pin1 = execution.entry.organizationPin1() else {
            throw Failure.pin1Unavailable
          }
          return try Self.readOrganization(
            channel: channel,
            pin1: pin1,
            execution: execution)
        }
      }
    }

    /// PACE with the proven access number, then the secured reads.
    ///
    /// A transport answer that stops inside the secured reads is
    /// interrupted communication: the card was found and the channel
    /// was open, so it is named as itself rather than folded into
    /// the generic unread-card sentence.
    private static func readPersonal(
      channel: SmartCardChannel,
      proven: ProvenAccessNumber,
      sheet: NearFieldSheet,
      isRecovery: Bool,
      store: @escaping StorePersonalIdentity
    ) throws -> HoldRead {
      let keys = try Self.establishPace(
        channel: channel,
        accessNumber: proven.value,
        sheet: sheet,
        isRecovery: isRecovery)
      OperationPhaseTrace.mark("priming-pace-done")
      let saved = CardCredentialStore.save(cardAccessNumber: proven.digits)
      guard saved == errSecSuccess else { throw Self.storeFailure(saved) }
      let payload: Payload
      do {
        payload = try Self.readSecuredPayload(
          operations: CardOperations(
            channel: SecureMessagingChannel(wrapping: channel, sessionKeys: keys)),
          sheet: sheet,
          store: { identity in try store(identity, proven) })
      } catch SmartCardChannel.TransportError.responseTimedOut,
        CardOperationError.exchangeUnanswered,
        CardOperationError.sessionUnavailable
      {
        throw Failure.communicationInterrupted
      }
      OperationPhaseTrace.mark("priming-secured-read-done")
      return HoldRead(
        instance: payload.identity.instance,
        credentialReport: payload.credentialReport)
    }

    /// Runs PACE against the card, managing recovery feedback and error translation.
    private static func establishPace(
      channel: SmartCardChannel,
      accessNumber: CardAccessNumber,
      sheet: NearFieldSheet,
      isRecovery: Bool
    ) throws -> PaceSessionKeys {
      // PACE runs from the main file. The card was discovered by
      // selecting an application, and MSE:Set AT from an applet context
      // is answered 6985, so the main file is made current on the plain
      // channel before the first PACE command.
      //
      // Best effort on purpose: card generations differ in which SELECT
      // variant they acknowledge, and one that refuses both may still be
      // at the main file. PACE itself is the authoritative check --
      // its first command is the one that has to be accepted -- so a
      // refused reposition is not turned into a failure here.
      try? CardOperations(channel: channel).selectMainFile()
      if isRecovery {
        sheet.startRecovery()
      }
      defer {
        sheet.stopRecovery()
      }
      OperationPhaseTrace.mark("priming-pace-begin")
      do {
        return try PaceEstablishment(channel: channel).establish(
          with: PacePassword(cardAccessNumber: accessNumber)
        ).keys
      } catch SmartCardChannel.TransportError.responseTimedOut {
        OperationPhaseTrace.mark("priming-pace-timed-out")
        throw Failure.secureChannelTimedOut
      } catch PaceEstablishment.Failure.authenticationTokenMismatch,
        PaceEstablishment.Failure.cardRejected(.authenticationFailed)
      {
        // PACE is the access number's proof: the session keys derive
        // from it, so a card that will not agree is a card these
        // digits do not describe. A FINEID card may answer with 6300.
        throw Failure.wrongCardAccessNumber
      }
    }

    /// Runs one blocking card exchange off the cooperative pool.
    internal static func onCardQueue<Value: Sendable>(
      _ body: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
      try await withCheckedThrowingContinuation { continuation in
        Self.cardQueue.async {
          continuation.resume(with: Result { try body() })
        }
      }
    }
  }

#endif
