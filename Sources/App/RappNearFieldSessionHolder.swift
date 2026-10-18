// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation
  import UIKit

  /// Holds the near-field card session, its exclusive card session and the
  /// PACE secure channel across consecutive remote operations, so a login
  /// that asks twice pays for the field and the handshake once.
  ///
  /// The hold follows ``CardSessionHold``: it ends when the card leaves,
  /// after ``CardSessionHold/idleLimitSeconds`` without an operation, when
  /// the app goes to the background, and when an operation ends without
  /// the card answering.
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
    /// channel; one operation uses them at a time, which the actor
    /// serialises, so the channel's sequence counter is never raced.
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
    private var hold = CardSessionHold()
    private var expirationTask: Task<Void, Never>?
    private var credentials = CredentialSessionState()

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

    /// Whether the card answered the operation: a result or a credential
    /// the card itself refused.
    private static func cardAnswered(_ outcome: RappCardExecutor.Outcome?) -> Bool {
      switch outcome {
      case .result, .rejected:
        true

      case .completionAmbiguous, .refusedBeforeCredentialTransmit, nil:
        false
      }
    }

    /// The continuous clock the hold's idle limit is measured on.
    private static func nowMs() -> Int64 {
      Int64(clamping: RappPlatformClock().monotonicMilliseconds())
    }

    internal func registerNegativePin(_ digits: String) {
      credentials.recordNegativePin(digits)
    }

    internal func setPin1Authenticated(_ value: Bool) {
      if value {
        credentials.markPin1Authenticated()
      }
    }

    internal func insertProbedRole(_ role: CredentialRole) {
      credentials.markProbed(role)
    }

    internal func execute(
      cardAccessNumber: String,
      message: String,
      _ operation: @escaping @Sendable (CardOperations, Context) -> RappCardExecutor.Outcome
    ) async -> RappCardExecutor.Outcome? {
      expirationTask?.cancel()
      expirationTask = nil

      guard let currentSession = await obtainSession(message: message) else {
        return nil
      }

      if currentSession.wasPrompted {
        currentSession.update(message: String(localized: "Card found. Keep holding."))
        await MainActor.run {
          CardPrimingFeedback.startWorking()
        }
      }

      let context = makeContext()
      let result = await performWithSession(
        currentSession,
        cardAccessNumber: cardAccessNumber,
        context: context,
        operation: operation
      )
      await reportFeedback(for: result, session: currentSession)
      settle(outcome: result)
      return result
    }

    internal func closeSession() {
      end(hold.closedByOwner())
      releaseEverything()
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
      credentials.sessionEnded()
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
        credentials.sessionEnded()
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
      let snapshot = credentials
      return Context(
        isPin1Authenticated: snapshot.isPin1Authenticated,
        isRoleProbed: { role in snapshot.probedRoles.contains(role) },
        isNegativePin: { digits in snapshot.isNegativePin(digits) },
        markPin1Authenticated: { [weak self] in
          Task { await self?.setPin1Authenticated(true) }
        },
        markRoleProbed: { [weak self] role in
          Task { await self?.insertProbedRole(role) }
        },
        recordNegativePin: { [weak self] digits in
          Task { await self?.registerNegativePin(digits) }
        }
      )
    }

    /// The held channel, opened and prepared with PACE when none is held.
    private func preparedChannel(
      _ session: NearFieldCardSession,
      cardAccessNumber: String
    ) async -> HeldChannel? {
      if let heldChannel { return heldChannel }
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
      hold.sessionOpened()
      hold.channelPrepared()
      heldChannel = prepared
      return prepared
    }

    private func performWithSession(
      _ session: NearFieldCardSession,
      cardAccessNumber: String,
      context: Context,
      operation: @escaping @Sendable (CardOperations, Context) -> RappCardExecutor.Outcome
    ) async -> RappCardExecutor.Outcome? {
      guard let held = await preparedChannel(session, cardAccessNumber: cardAccessNumber) else {
        #if DEBUG
          HolderTrace.say("performWithSession: no prepared channel")
        #endif
        return nil
      }
      hold.operationStarted()
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
