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
    /// Runs on the card queue, inside the card's exclusive session. The
    /// card's first answer names its kind before any password is sent
    /// (``ContactlessCardKind``); a hold whose entry is for the other kind,
    /// or that has none, ends there with ``Failure/cardKind(_:)``.
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
      let waitBudget: SmartCardChannel.ResponseWait = isRecovery ? .nearFieldRecovery : .nearField
      return try execution.session.withCardSession(waits: waitBudget) { channel in
        let kind = ContactlessCardKind.of(CardOperations(channel: channel))
        guard let password = execution.password, password.kind == kind else {
          throw Failure.cardKind(kind)
        }
        switch password {
        case .cardAccessNumber(let proven):
          let keys = try Self.establishPace(
            channel: channel,
            accessNumber: proven.value,
            sheet: sheet,
            isRecovery: isRecovery)
          let payload = try Self.readSecuredPayload(
            operations: CardOperations(
              channel: SecureMessagingChannel(wrapping: channel, sessionKeys: keys)),
            sheet: sheet,
            store: { identity in try store(identity, proven) })
          return HoldRead(
            instance: payload.identity.instance,
            credentialReport: payload.credentialReport)

        case .organizationPin1(let pin1):
          return try Self.readOrganization(
            channel: channel,
            pin1: pin1,
            execution: execution)
        }
      }
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
      do {
        return try PaceEstablishment(channel: channel).establish(
          with: PacePassword(cardAccessNumber: accessNumber)
        ).keys
      } catch SmartCardChannel.TransportError.responseTimedOut {
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
