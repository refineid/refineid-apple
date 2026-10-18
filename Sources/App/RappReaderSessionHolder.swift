// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import CryptoTokenKit
  import Foundation
  import UIKit

  /// Holds the attached reader's card session and its selected channel
  /// across remote operations, and opens it before the first request
  /// arrives, so a browser request pays for the PIN and the signature
  /// only.
  ///
  /// The hold follows ``CardSessionHold`` without a session life limit: a
  /// reader keeps its card powered. Preparation, operations and the app's
  /// own claim on the reader join one chain, so none cuts another.
  internal actor RappReaderSessionHolder {
    /// The exclusive card session and the operations over its channel;
    /// the chain hands them to one operation at a time.
    private final class HeldChannel: @unchecked Sendable {
      let session: SmartCardChannel.OpenSession
      let operations: CardOperations

      init(session: SmartCardChannel.OpenSession, operations: CardOperations) {
        self.session = session
        self.operations = operations
      }
    }

    /// How opening the reader card ended.
    private enum Opening {
      case opened(HeldChannel)
      case noCard
      case wrongCardAccessNumber
      case failed
    }

    internal static let shared = RappReaderSessionHolder()

    private var heldChannel: HeldChannel?
    private var hold = CardSessionHold(sessionLimitSeconds: nil)
    private var expirationTask: Task<Void, Never>?
    private let credentials = CredentialSessionBox()

    /// The end of the chain; a caller joins behind it.
    private var chain: Task<Void, Never>?

    /// The background observation, held for the actor's lifetime.
    private var backgroundObserver: (any NSObjectProtocol)?

    private init() {
      backgroundObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.didEnterBackgroundNotification,
        object: nil,
        queue: nil
      ) { _ in
        Task { await RappReaderSessionHolder.shared.appBackgrounded() }
      }
    }

    /// Whether the card answered the operation.
    ///
    /// A session failure and an ambiguous completion are the card not
    /// answering; a local refusal or a credential the card refused leave
    /// the channel sound.
    private static func cardAnswered(_ outcome: RappCardExecutor.Outcome) -> Bool {
      switch outcome {
      case .result, .rejected:
        true

      case .refusedBeforeCredentialTransmit(let refusal):
        refusal != .cardUnavailable

      case .completionAmbiguous:
        false
      }
    }

    /// The continuous clock the hold's limits are measured on.
    private static func nowMs() -> Int64 {
      Int64(clamping: RappPlatformClock().monotonicMilliseconds())
    }

    /// Opens the first occupied reader's card and selects the application,
    /// with the same card access number the operation path offers.
    private static func open(cardAccessNumber: String?) async -> Opening {
      guard let manager = TKSmartCardSlotManager.default else { return .noCard }
      let occupied = await CardSlotSearch.allOccupied(in: manager).filter { occupiedSlot in
        CardTransport.transport(forSlotNamed: occupiedSlot.name) == .reader
      }
      let cards = occupied.compactMap { occupiedSlot in
        occupiedSlot.slot.makeSmartCard().map(CardMaintenance.UncheckedCard.init)
      }
      guard !cards.isEmpty else { return .noCard }
      return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          for candidate in cards {
            let opening = openSession(candidate, cardAccessNumber: cardAccessNumber)
            if case .failed = opening { continue }
            continuation.resume(returning: opening)
            return
          }
          continuation.resume(returning: .failed)
        }
      }
    }

    private static func openSession(
      _ candidate: CardMaintenance.UncheckedCard,
      cardAccessNumber: String?
    ) -> Opening {
      guard let open = try? SmartCardChannel(candidate.card).openSession() else {
        return .failed
      }
      OperationPhaseTrace.mark("slot-session-begun")
      do {
        let operations = try CardMaintenance.connectionOperations(
          over: open.channel,
          cardAccessNumber: cardAccessNumber
        )
        OperationPhaseTrace.mark("pace-done")
        return .opened(HeldChannel(session: open, operations: operations))
      } catch CardMaintenance.ConnectionFailure.wrongCardAccessNumber {
        open.end()
        return .wrongCardAccessNumber
      } catch {
        open.end()
        return .failed
      }
    }

    /// Opens the reader card and selects the application ahead of a
    /// request, behind any operation under way; nothing happens when a
    /// session is held or no reader card is attached.
    internal func prepare() async {
      await serialized {
        await self.runPrepare()
      }
    }

    /// Runs one remote operation on the reader card behind any operation
    /// under way, or nil when no reader card is attached.
    internal func execute(
      cardAccessNumber: String?,
      _ operation:
        @escaping @Sendable (
          CardOperations,
          RappNearFieldSessionHolder.Context?
        ) -> RappCardExecutor.Outcome
    ) async -> CardMaintenance.CardSessionResult<RappCardExecutor.Outcome>? {
      await serialized {
        await self.run(cardAccessNumber: cardAccessNumber, operation)
      }
    }

    /// Ends the hold once the operation under way has finished, so the
    /// app's own card work can take the reader.
    internal func yield() async {
      await serialized {
        await self.close()
      }
    }

    internal func close() {
      end(hold.closedByOwner())
    }

    internal func cardLeft() {
      end(hold.cardLeft())
    }

    /// Runs `body` after every chained call before it has finished.
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

    private func runPrepare() async {
      guard heldChannel == nil else { return }
      guard case .opened(let held) = await Self.open(cardAccessNumber: nil) else { return }
      adopt(held)
      armIdleLimit()
    }

    private func run(
      cardAccessNumber: String?,
      _ operation:
        @escaping @Sendable (
          CardOperations,
          RappNearFieldSessionHolder.Context?
        ) -> RappCardExecutor.Outcome
    ) async -> CardMaintenance.CardSessionResult<RappCardExecutor.Outcome>? {
      expirationTask?.cancel()
      expirationTask = nil
      let held: HeldChannel
      if let current = heldChannel, hold.reusesChannel {
        held = current
      } else {
        end(hold.closedByOwner())
        switch await Self.open(cardAccessNumber: cardAccessNumber) {
        case .opened(let opened):
          adopt(opened)
          held = opened

        case .noCard:
          return nil

        case .wrongCardAccessNumber:
          return .wrongCardAccessNumber

        case .failed:
          return .failed
        }
      }
      _ = hold.startsOperation(nowMs: Self.nowMs())
      let context = makeContext()
      let outcome: RappCardExecutor.Outcome = await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          continuation.resume(returning: operation(held.operations, context))
        }
      }
      settle(outcome: outcome)
      return .connected(outcome)
    }

    private func appBackgrounded() {
      end(hold.appBackgrounded())
    }

    private func adopt(_ held: HeldChannel) {
      heldChannel = held
      hold.sessionOpened(nowMs: Self.nowMs())
      hold.channelPrepared()
      credentials.mutate { $0.sessionEnded() }
    }

    /// Releases the session whatever the hold said, recording an ending.
    private func end(_ verdict: CardSessionHold.Verdict) {
      if case .end = verdict {
        OperationPhaseTrace.mark("session-ended")
      }
      heldChannel?.session.end()
      heldChannel = nil
      expirationTask?.cancel()
      expirationTask = nil
      credentials.mutate { $0.sessionEnded() }
    }

    private func settle(outcome: RappCardExecutor.Outcome) {
      let verdict = hold.operationFinished(
        answered: Self.cardAnswered(outcome),
        nowMs: Self.nowMs()
      )
      guard case .keep = verdict else {
        end(verdict)
        return
      }
      armIdleLimit()
    }

    private func armIdleLimit() {
      expirationTask?.cancel()
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
    }

    private func makeContext() -> RappNearFieldSessionHolder.Context {
      let snapshot = credentials.read()
      let box = credentials
      return RappNearFieldSessionHolder.Context(
        isPin1Authenticated: snapshot.isPin1Authenticated,
        isRoleProbed: { role in snapshot.probedRoles.contains(role) },
        isNegativePin: { digits in snapshot.isNegativePin(digits) },
        markPin1Authenticated: { box.mutate { $0.markPin1Authenticated() } },
        markRoleProbed: { role in box.mutate { $0.markProbed(role) } },
        recordNegativePin: { digits in box.mutate { $0.recordNegativePin(digits) } }
      )
    }
  }
#endif
