// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation
  import UIKit

  /// Holds the near-field card session, its exclusive card session and the
  /// PACE secure channel across consecutive remote operations, so a login
  /// that asks twice pays for the field and the handshake once.
  ///
  /// The hold follows ``CardSessionHold`` with the near-field session
  /// life: it ends when the card leaves, after the idle limit, before the
  /// system invalidates the session, when the app goes to the background,
  /// and when an operation ends without the card answering. Operations
  /// join one chain, so two never touch the channel at once.
  internal actor RappNearFieldSessionHolder {
    internal struct Context: Sendable {
      internal let isRoleProbed: @Sendable (CredentialRole) -> Bool
      internal let isNegativePin: @Sendable (String) -> Bool
      internal let markRoleProbed: @Sendable (CredentialRole) -> Void
      internal let recordNegativePin: @Sendable (String, CredentialRole) -> Void
    }

    /// The exclusive card session and the operations over its secure
    /// channel; the operation chain hands them to one operation at a
    /// time, so the channel's sequence counter is never raced.
    internal static let shared = RappNearFieldSessionHolder()

    internal var activeSession: NearFieldCardSession?
    internal var heldChannel: RappHeldCardChannel?
    internal var hold = CardSessionHold(
      sessionLimitSeconds: CardSessionHold.nearFieldSessionLimitSeconds)
    internal var expirationTask: Task<Void, Never>?
    internal var keepAlive: Task<Bool, Never>?
    private let credentials = CredentialSessionBox()

    /// Every use of the channel, and every close, runs on this chain.
    private let chain = SerialChain()

    /// The background observation, held for the actor's lifetime.
    private var backgroundObserver: (any NSObjectProtocol)?

    private init() {
      backgroundObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.didEnterBackgroundNotification,
        object: nil,
        queue: nil
      ) { _ in
        Task { await RappNearFieldSessionHolder.shared.appBackgrounded() }
      }
    }

    /// Whether the card answered the operation.
    ///
    /// A session failure and an ambiguous completion are the card not
    /// answering; a local refusal or a credential the card refused leave
    /// the channel sound.
    /// The continuous clock the hold's limits are measured on.
    internal static func nowMs() -> Int64 {
      Int64(clamping: RappPlatformClock().monotonicMilliseconds())
    }

    internal func execute(
      cardAccessNumber: String,
      message: String,
      _ operation: @escaping @Sendable (CardOperations, Context) -> RappCardExecutor.Outcome
    ) async -> RappCardExecutor.Outcome? {
      await chain.run {
        await self.run(cardAccessNumber: cardAccessNumber, message: message, operation)
      }
    }

    /// Ends the hold once the operation under way has finished.
    internal func closeSession() async {
      await chain.run {
        await self.release()
      }
    }

    private func run(
      cardAccessNumber: String,
      message: String,
      _ operation: @escaping @Sendable (CardOperations, Context) -> RappCardExecutor.Outcome
    ) async -> RappCardExecutor.Outcome? {
      expirationTask?.cancel()
      expirationTask = nil
      await settleKeepAlive()
      // A session too old or too idle for another operation ends here, so
      // the request opens a fresh one instead of meeting an invalidated
      // field mid-command.
      let verdict = hold.tick(nowMs: Self.nowMs())
      if case .end = verdict {
        end(verdict)
        releaseEverything()
      }
      guard let currentSession = await obtainSession(message: message) else {
        return nil
      }
      // The sheet says what is happening whether the card was waited for
      // or lay there already: the read takes seconds either way.
      currentSession.update(message: String(localized: "Card found. Keep holding."))
      await MainActor.run {
        CardPrimingFeedback.startWorking()
      }
      let result = await performWithSession(
        currentSession,
        cardAccessNumber: cardAccessNumber,
        operation: operation
      )
      await reportFeedback(for: result, session: currentSession)
      settle(outcome: result)
      return result
    }

    private func appBackgrounded() async {
      await chain.run {
        await self.releaseForBackground()
      }
    }

    private func releaseForBackground() async {
      await settleKeepAlive()
      end(hold.appBackgrounded())
      releaseEverything()
    }

    /// Ends the hold by its owner's word and releases everything.
    private func release() async {
      await settleKeepAlive()
      end(hold.closedByOwner())
      releaseEverything()
    }

    /// Ends the held card session and the field, whatever the hold said.
    internal func releaseEverything() {
      PrimeStore.clearRegistrationField()
      heldChannel?.session.end()
      heldChannel = nil
      activeSession?.end()
      activeSession = nil
      expirationTask?.cancel()
      expirationTask = nil
      credentials.mutate { $0.sessionEnded() }
      Task { @MainActor in
        CardPrimingFeedback.stopWorking()
      }
    }

    /// Records an ending in the trace; the caller releases the resources.
    internal func end(_ verdict: CardSessionHold.Verdict) {
      guard case .end = verdict else { return }
      OperationPhaseTrace.mark("session-ended")
    }

    private func obtainSession(message: String) async -> NearFieldCardSession? {
      if let existing = activeSession {
        guard existing.holdsValidCard else {
          #if DEBUG
            HolderTrace.say("obtainSession: held slot state \(existing.slotState.traceName)")
          #endif
          end(hold.cardLeft())
          releaseEverything()
          return await obtainSession(message: message)
        }
        return existing
      }
      do {
        // The system's session life runs from this request, before the
        // card is even in the field, so the hold's clock starts here.
        let startedAtMs = Self.nowMs()
        let session = try await NearFieldCardSession.open(
          message: message,
          onPromptNeeded: {
            Task { @MainActor in
              UISoundLibrary.play(named: "Handoff-EncoreInfinitum")
            }
          }
        )
        activeSession = session
        hold.sessionOpened(nowMs: startedAtMs)
        credentials.mutate { $0.sessionEnded() }
        return session
      } catch {
        #if DEBUG
          HolderTrace.say("obtainSession failed: \(error)")
        #endif
        end(hold.commandFailed())
        releaseEverything()
        return nil
      }
    }

    /// The held channel when the hold allows its reuse; otherwise a fresh
    /// one, opened and prepared with PACE.
    private func preparedChannel(
      _ session: NearFieldCardSession,
      cardAccessNumber: String
    ) async -> RappHeldCardChannel? {
      if let heldChannel, hold.reusesChannel { return heldChannel }
      heldChannel?.session.end()
      heldChannel = nil
      let prepared: RappHeldCardChannel? = await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          guard let open = try? session.openCardSession() else {
            continuation.resume(returning: nil)
            return
          }
          OperationPhaseTrace.mark("slot-session-begun")
          guard
            let operations = CardMaintenance.selectedOperations(
              over: open.channel,
              cardAccessNumber: cardAccessNumber
            )
          else {
            open.end()
            continuation.resume(returning: nil)
            return
          }
          OperationPhaseTrace.mark("pace-done")
          continuation.resume(returning: RappHeldCardChannel(session: open, operations: operations))
        }
      }
      guard let prepared else { return nil }
      hold.channelPrepared()
      credentials.mutate { $0.sessionEnded() }
      heldChannel = prepared
      return prepared
    }

    private func performWithSession(
      _ session: NearFieldCardSession,
      cardAccessNumber: String,
      operation: @escaping @Sendable (CardOperations, Context) -> RappCardExecutor.Outcome
    ) async -> RappCardExecutor.Outcome? {
      guard let held = await preparedChannel(session, cardAccessNumber: cardAccessNumber) else {
        #if DEBUG
          HolderTrace.say("performWithSession: no prepared channel")
        #endif
        return nil
      }
      // The session may have aged since the request's tick; an aged one
      // is released, and the request reports the card unavailable rather
      // than running on a field the system is about to invalidate.
      let verdict = hold.startsOperation(nowMs: Self.nowMs())
      if case .end = verdict {
        end(verdict)
        releaseEverything()
        return .refusedBeforeCredentialTransmit(.cardUnavailable)
      }
      let context = Context.live(on: credentials)
      let answer: RappCardExecutor.Outcome = await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          continuation.resume(returning: operation(held.operations, context))
        }
      }
      #if DEBUG
        HolderTrace.say("performWithSession: outcome=\(answer)")
      #endif
      return answer
    }
  }
#endif
