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
      internal let isPin1Authenticated: Bool
      internal let isRoleProbed: @Sendable (CredentialRole) -> Bool
      internal let isNegativePin: @Sendable (String) -> Bool
      internal let markPin1Authenticated: @Sendable () -> Void
      internal let markRoleProbed: @Sendable (CredentialRole) -> Void
      internal let recordNegativePin: @Sendable (String) -> Void
    }

    /// The exclusive card session and the operations over its secure
    /// channel; the operation chain hands them to one operation at a
    /// time, so the channel's sequence counter is never raced.
    private final class HeldChannel: @unchecked Sendable {
      let session: SmartCardChannel.OpenSession
      let operations: CardOperations

      init(session: SmartCardChannel.OpenSession, operations: CardOperations) {
        self.session = session
        self.operations = operations
      }
    }

    internal static let shared = RappNearFieldSessionHolder()

    private var activeSession: NearFieldCardSession?
    private var heldChannel: HeldChannel?
    private var hold = CardSessionHold(
      sessionLimitSeconds: CardSessionHold.nearFieldSessionLimitSeconds)
    private var expirationTask: Task<Void, Never>?
    private let credentials = CredentialSessionBox()

    /// The end of the operation chain; a caller joins behind it.
    private var chain: Task<Void, Never>?

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
    private static func cardAnswered(_ outcome: RappCardExecutor.Outcome?) -> Bool {
      switch outcome {
      case .result, .rejected:
        true

      case .refusedBeforeCredentialTransmit(let refusal):
        refusal != .cardUnavailable

      case .completionAmbiguous, nil:
        false
      }
    }

    /// The continuous clock the hold's limits are measured on.
    private static func nowMs() -> Int64 {
      Int64(clamping: RappPlatformClock().monotonicMilliseconds())
    }

    internal func execute(
      cardAccessNumber: String,
      message: String,
      _ operation: @escaping @Sendable (CardOperations, Context) -> RappCardExecutor.Outcome
    ) async -> RappCardExecutor.Outcome? {
      await serialized {
        await self.run(cardAccessNumber: cardAccessNumber, message: message, operation)
      }
    }

    internal func closeSession() {
      end(hold.closedByOwner())
      releaseEverything()
    }

    /// Runs `body` after every operation before it has finished.
    private func serialized<Value: Sendable>(
      _ body: @escaping @Sendable () async -> Value
    ) async -> Value {
      let previous = chain
      let task = Task { () -> Value in
        await previous?.value
        return await body()
      }
      chain = Task { _ = await task.value }
      return await task.value
    }

    private func run(
      cardAccessNumber: String,
      message: String,
      _ operation: @escaping @Sendable (CardOperations, Context) -> RappCardExecutor.Outcome
    ) async -> RappCardExecutor.Outcome? {
      expirationTask?.cancel()
      expirationTask = nil
      // A session too old to finish another operation ends here, so the
      // request below opens a fresh one instead of meeting an invalidated
      // field mid-command.
      if case .end = hold.tick(nowMs: Self.nowMs()) {
        end(.end(.sessionAged))
        releaseEverything()
      }
      guard let currentSession = await obtainSession(message: message) else {
        return nil
      }
      if currentSession.wasPrompted {
        currentSession.update(message: String(localized: "Card found. Keep holding."))
        await MainActor.run {
          CardPrimingFeedback.startWorking()
        }
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

    private func appBackgrounded() {
      end(hold.appBackgrounded())
      releaseEverything()
    }

    /// Ends the held card session and the field, whatever the hold said.
    private func releaseEverything() {
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
    private func end(_ verdict: CardSessionHold.Verdict) {
      guard case .end = verdict else { return }
      OperationPhaseTrace.mark("session-ended")
    }

    private func obtainSession(message: String) async -> NearFieldCardSession? {
      if let existing = activeSession {
        guard existing.holdsValidCard else {
          end(hold.cardLeft())
          releaseEverything()
          return await obtainSession(message: message)
        }
        return existing
      }
      do {
        let session = try await NearFieldCardSession.open(
          message: message,
          onPromptNeeded: {
            Task { @MainActor in
              UISoundLibrary.play(named: "Handoff-EncoreInfinitum")
            }
          }
        )
        activeSession = session
        credentials.mutate { $0.sessionEnded() }
        return session
      } catch {
        #if DEBUG
          HolderTrace.say("obtainSession failed: \(error)")
        #endif
        closeSession()
        return nil
      }
    }

    private func makeContext() -> Context {
      let snapshot = credentials.read()
      let box = credentials
      return Context(
        isPin1Authenticated: snapshot.isPin1Authenticated,
        isRoleProbed: { role in snapshot.probedRoles.contains(role) },
        isNegativePin: { digits in snapshot.isNegativePin(digits) },
        markPin1Authenticated: { box.mutate { $0.markPin1Authenticated() } },
        markRoleProbed: { role in box.mutate { $0.markProbed(role) } },
        recordNegativePin: { digits in box.mutate { $0.recordNegativePin(digits) } }
      )
    }

    /// The held channel when the hold allows its reuse; otherwise a fresh
    /// one, opened and prepared with PACE.
    private func preparedChannel(
      _ session: NearFieldCardSession,
      cardAccessNumber: String
    ) async -> HeldChannel? {
      if let heldChannel, hold.reusesChannel { return heldChannel }
      heldChannel?.session.end()
      heldChannel = nil
      let prepared: HeldChannel? = await withCheckedContinuation { continuation in
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
          continuation.resume(returning: HeldChannel(session: open, operations: operations))
        }
      }
      guard let prepared else { return nil }
      hold.sessionOpened(nowMs: Self.nowMs())
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
      _ = hold.startsOperation(nowMs: Self.nowMs())
      let context = makeContext()
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

    /// Keeps or ends the hold after an operation, and arms the idle limit.
    private func settle(outcome: RappCardExecutor.Outcome?) {
      let verdict = hold.operationFinished(
        answered: Self.cardAnswered(outcome),
        nowMs: Self.nowMs()
      )
      guard case .keep = verdict, activeSession?.holdsValidCard == true else {
        end(verdict)
        releaseEverything()
        return
      }
      expirationTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(CardSessionHold.idleLimitSeconds))
        guard !Task.isCancelled else { return }
        await self?.idleExpired()
      }
    }

    private func idleExpired() {
      let verdict = hold.tick(nowMs: Self.nowMs())
      guard case .end = verdict else { return }
      end(verdict)
      releaseEverything()
    }
  }
#endif
