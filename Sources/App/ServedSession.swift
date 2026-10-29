// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation
  import RappEngine

  /// One authenticated RAPP session the phone serves: one stream
  /// connection, one Bluetooth link, or the nearby connection (RAPP
  /// v26.10.29 §8.3).
  ///
  /// Every session runs apart from the others: its own coordinator and
  /// dispatcher, its own ordered frame delivery, liveness, close and
  /// `card.status`. Its operations take the card through the custodian's
  /// one queue (§8.2 item 2): an operation joins when it is admitted, its
  /// session hears `queued` while another session's operation holds the
  /// card, and it reads, prompts, summons or commands the card only once it
  /// holds it. The coordinator's events are taken as they come; the
  /// dispatcher's steps run one after another on the session's own chain,
  /// so a prompt holds up no event of this session or any other, and a close
  /// or an expiry reaches the dispatcher while the prompt is up.
  @MainActor
  internal final class ServedSession {
    /// The card turn of one operation of one session.
    internal struct Turn: Hashable, Sendable {
      /// The session the operation belongs to.
      internal let session: UUID
      /// The operation.
      internal let operation: RappOperationIdentifier
    }

    /// What the session tells the relay.
    internal enum Report: Equatable {
      /// The session ended; it reports nothing more.
      case closed(RappConnectionCoordinator.CloseReason)
      /// The handshake completed; the custodian's first word is due.
      case established
      /// The peer sent frames faster than they could be delivered.
      case frameOverrun
      /// An operation is over and nothing of it holds the card.
      case operationOver
    }

    /// One operation's hold on the card.
    private struct Run {
      /// Whether the operation is over: answered, expired or ended with the
      /// session.
      var isOver = false
      /// The dispatcher's steps of it started and not yet finished.
      var stepsRunning = 0
    }

    // MARK: Properties

    /// Names this session apart from every other the phone served.
    internal let identifier = UUID()
    /// The connection the session runs over.
    internal let transport: ServedTransport
    /// The pairing the session runs over.
    internal let pairID: Data
    /// The session's protocol state.
    internal let coordinator: RappConnectionCoordinator
    /// Whether the handshake completed.
    internal private(set) var isEstablished = false
    /// Whether the session ended.
    internal private(set) var hasEnded = false

    private let dispatcher: RappPhoneProxyDispatcher
    private let cardQueue: CustodianCardQueue<Turn>
    private let report: (ServedSession, Report) -> Void
    /// Frames enter the coordinator in arrival order through this bounded
    /// chain.
    private let frameDelivery = OrderedDelivery(capacity: OrderedDelivery.relayFrameCapacity)
    /// The operations that hold or wait for the card, or whose steps still
    /// run.
    private var runs: [RappOperationIdentifier: Run] = [:]
    /// The step started last; the next one runs after it.
    private var stepTail: Task<Void, Never>?

    // MARK: Computed Properties

    /// Whether no operation of the session is live.
    internal var isIdle: Bool {
      runs.isEmpty
    }

    // MARK: Lifecycle

    /// A session over `pairID` on `transport`, driven by `coordinator`,
    /// taking the card through `cardQueue` and reporting to `report`.
    internal init(
      transport: ServedTransport,
      pairID: Data,
      coordinator: RappConnectionCoordinator,
      cardQueue: CustodianCardQueue<Turn>,
      report: @escaping (ServedSession, Report) -> Void
    ) {
      self.transport = transport
      self.pairID = pairID
      self.coordinator = coordinator
      self.cardQueue = cardQueue
      self.report = report
      dispatcher = RappPhoneProxyDispatcher(
        inbox: RappAuthorizationInbox.shared, pairID: pairID, session: identifier)
    }

    // MARK: Functions

    /// Starts the handshake, then feeds the frames that came before it.
    internal func start(earlyFrames: [Data]) {
      Task { [coordinator] in
        for await event in coordinator.events {
          receive(event)
        }
      }
      // The replay joins the same chain later frames append to, so a frame
      // arriving during the replay cannot overtake it.
      deliverInOrder { [coordinator] in
        await coordinator.start()
        for frame in earlyFrames {
          await coordinator.receive(frame)
        }
      }
    }

    /// Delivers one frame the transport received.
    internal func receive(_ frame: Data) {
      deliverInOrder { [coordinator] in await coordinator.receive(frame) }
    }

    /// The transport closed under the session.
    internal func transportClosed() {
      Task { [coordinator] in await coordinator.transportClosed() }
    }

    /// Ends the session at once, without waiting for its close to travel.
    internal func close() {
      Task { [coordinator] in
        await coordinator.transportClosed()
        await coordinator.close()
      }
    }

    private func deliverInOrder(_ work: @escaping @Sendable () async -> Void) {
      guard !frameDelivery.deliver(work) else { return }
      report(self, .frameOverrun)
    }

    private func receive(_ event: RappConnectionCoordinator.Event) {
      #if DEBUG
        HolderTrace.say("session event \(eventCaseName(event))")
      #endif
      switch event {
      case .established:
        isEstablished = true
        report(self, .established)

      case .inspectPrerequisites(let operationID, _):
        runs[operationID] = Run()
        runStep(of: operationID) { [self] in
          guard await takeCard(for: operationID) else { return }
          await dispatcher.receive(event, from: coordinator)
        }

      case .awaitUserApproval(let operationID, _), .executeSafeRead(let operationID, _),
        .executeCardCommand(let operationID, _):
        runStep(of: operationID) { [self] in
          await dispatcher.receive(event, from: coordinator)
        }

      case .answered(let operationID), .completed(let operationID, _),
        .terminal(let operationID, _), .operationEnded(.cardExchangeContinues(let operationID)),
        .operationEnded(.dropped(let operationID)):
        operationOver(operationID)
        tellDispatcher(event)

      case .closed(let reason):
        ended()
        tellDispatcher(event)
        report(self, .closed(reason))

      case .progress, .cardStatus:
        break
      }
    }

    /// Hands `event` to the dispatcher beside any step under way: it takes
    /// down what is left of an operation, its prompt included.
    private func tellDispatcher(_ event: RappConnectionCoordinator.Event) {
      Task { [dispatcher, coordinator] in await dispatcher.receive(event, from: coordinator) }
    }

    /// Runs `body`, a dispatcher step of `operationID`, after every step
    /// started before it.
    private func runStep(
      of operationID: RappOperationIdentifier, _ body: @escaping @MainActor () async -> Void
    ) {
      runs[operationID]?.stepsRunning += 1
      let previous = stepTail
      stepTail = Task {
        await previous?.value
        await body()
        runs[operationID]?.stepsRunning -= 1
        settle(operationID)
      }
    }

    /// Joins the card queue for `operationID` and waits for the card; false
    /// when the operation ended first.
    ///
    /// The requester hears `queued` while another session's operation holds
    /// the card.
    private func takeCard(for operationID: RappOperationIdentifier) async -> Bool {
      guard runs[operationID]?.isOver == false else { return false }
      let turn = Turn(session: identifier, operation: operationID)
      let granted = await cardQueue.take(turn) { [coordinator] in
        #if DEBUG
          HolderTrace.say("operation queued behind another session's")
        #endif
        try? await coordinator.reportProgress(operationID: operationID, event: .queued)
      }
      return granted && runs[operationID]?.isOver == false
    }

    private func operationOver(_ operationID: RappOperationIdentifier) {
      runs[operationID]?.isOver = true
      settle(operationID)
    }

    /// The session ended: every operation of it is over (§8.1 item 3), and
    /// its own summons goes.
    private func ended() {
      hasEnded = true
      HolderSummons.shared.cancel(owner: identifier)
      for operationID in Array(runs.keys) {
        operationOver(operationID)
      }
    }

    /// Lets the card go once `operationID` is over and no step of it runs:
    /// a waiting operation leaves the queue at once, while one holding the
    /// card keeps it until its card exchange has answered.
    private func settle(_ operationID: RappOperationIdentifier) {
      guard let run = runs[operationID], run.isOver else { return }
      let turn = Turn(session: identifier, operation: operationID)
      guard run.stepsRunning == 0 || cardQueue.holder != turn else { return }
      cardQueue.leave(turn)
      guard run.stepsRunning == 0 else { return }
      runs[operationID] = nil
      report(self, .operationOver)
    }
  }
#endif
