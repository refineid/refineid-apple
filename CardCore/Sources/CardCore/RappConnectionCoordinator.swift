// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import OSLog
  import RappEngine

  /// Runs one authenticated connection from Noise setup through card
  /// operations. All externally visible events are semantic and authenticated.
  public actor RappConnectionCoordinator {
    internal enum Phase: Equatable {
      case handshaking
      case operating
      /// This endpoint's close left before the session was established;
      /// the session driver waits for its echo.
      case closingHandshake
      /// This endpoint's close left on the established session; the
      /// operation driver waits for its echo.
      case closingOperation
      case closed
    }

    /// How often a session advances its liveness and checks the live
    /// operation's deadline; the engine decides when a ping is due (RAPP
    /// v26.11.2 §8.1 item 2, §8.3).
    public static let livenessPollIntervalMilliseconds: UInt64 = 1_000

    private static let logger = Logger(
      subsystem: "fi.refineid.ReFineID", category: "rapp-coordinator"
    )

    // MARK: Properties

    /// Connection events in order; the stream finishes after `closed`.
    nonisolated public let events: AsyncStream<Event>

    private let transport: any RappFrameTransport
    internal let handshake: RappSessionDriver
    private let maximumLifetimeMilliseconds: UInt64
    private let continuation: AsyncStream<Event>.Continuation
    internal var operation: RappOperationDriver?
    internal var phase = Phase.handshaking
    internal var livenessTask: Task<Void, Never>?
    /// Ends the wait for the echo of this endpoint's close at its bound.
    internal var echoTask: Task<Void, Never>?
    /// How long this endpoint waits for the echo of a close it sent (RAPP
    /// v26.11.2 §7.1 item 7).
    internal let closeEchoBoundMilliseconds = rappQuitWithdrawalBoundMs()
    /// Whether this endpoint's own close left on the transport.
    internal var ownCloseLeft = false
    /// Callers waiting for the connection to finish.
    internal var finishWaiters: [CheckedContinuation<Void, Never>] = []
    /// Why the connection closed, once it has.
    private var closeReason: CloseReason?

    // MARK: Lifecycle

    /// Prepares one connection over an established pair; ``start()`` sends
    /// the first frame. `transportProfile` names the transport the
    /// connection runs over, which the Noise prologue binds.
    public init(
      role: RappSessionDriver.Role,
      pair: RappPairRecord,
      displayName: RappDisplayName,
      transport: any RappFrameTransport,
      maximumLifetimeMilliseconds: UInt64,
      transportProfile: String = rappStreamProfileName(),
      clock: RappPlatformClock = RappPlatformClock()
    ) throws {
      self.transport = transport
      self.maximumLifetimeMilliseconds = maximumLifetimeMilliseconds
      self.handshake = try RappSessionDriver(
        role: role,
        pair: pair,
        displayName: displayName,
        transportProfile: transportProfile,
        clock: clock
      )

      var capturedContinuation: AsyncStream<Event>.Continuation?
      self.events = AsyncStream { capturedContinuation = $0 }
      guard let capturedContinuation else {
        preconditionFailure("AsyncStream did not provide a continuation")
      }
      self.continuation = capturedContinuation
    }

    // MARK: Functions

    /// Begins the Noise handshake once the transport is connected.
    public func start() async {
      guard phase == .handshaking else { return }
      await handleHandshake(await handshake.start())
    }

    /// Delivers one complete frame received by the transport.
    public func receive(_ frame: Data) async {
      switch phase {
      case .handshaking, .closingHandshake:
        await handleHandshake(await handshake.receive(frame))

      case .operating, .closingOperation:
        guard let operation else {
          await finish(.transportFailure)
          return
        }
        await handleOperation(await operation.receive(frame))

      case .closed:
        return
      }
    }

    /// Runs one liveness poll and deadline check; an operation cancelled
    /// for its deadline is reported answered, so its owner takes its prompt
    /// down (§8.1 item 2).
    public func pollLiveness() async {
      guard phase == .operating, let operation else { return }
      let expiry = await operation.expireDue()
      await handleOperation(expiry.commands)
      if let expired = expiry.expired { answered(expired) }
      guard phase == .operating else { return }
      await handleOperation(await operation.pollLiveness())
    }

    /// Reports that the transport closed without a local request.
    public func transportClosed() async {
      switch phase {
      case .handshaking, .closingHandshake:
        await handleHandshake(await handshake.transportClosed())

      case .operating, .closingOperation:
        guard let operation else {
          await finish(.transportFailure)
          return
        }
        await handleOperation(await operation.transportClosed())

      case .closed:
        return
      }
    }

    /// Closes the connection and finishes the event stream; the operation
    /// that ended with the session is reported before the close.
    public func close() async {
      switch phase {
      case .handshaking:
        _ = await handshake.close()

      case .operating:
        for command in await operation?.close() ?? [] {
          if let event = Event(command) { continuation.yield(event) }
        }

      case .closingHandshake:
        await handleHandshake(await handshake.close())
        return

      case .closingOperation:
        await handleOperation(await operation?.echoWaitEnded() ?? [])
        return

      case .closed:
        return
      }
      await finish(.localRequest)
    }

    internal func operationDriver() throws -> RappOperationDriver {
      guard phase == .operating, let operation else {
        throw RappOperationDriver.LocalError.wrongPhase
      }
      return operation
    }

    internal func handleHandshake(_ commands: [RappSessionDriver.Command]) async {
      for command in commands where phase == .handshaking || phase == .closingHandshake {
        switch command {
        case .send(let frame):
          do {
            try await transport.send(frame)
          } catch {
            _ = await handshake.transportClosed()
            await finish(.transportFailure)
          }

        case .peerNamed(let name):
          continuation.yield(.peerNamed(name))

        case .awaitCloseEcho:
          ownCloseLeft = true
          startEchoWait(.closingHandshake)

        case .established:
          do {
            operation = try await handshake.beginOperationDriver(
              maximumLifetimeMilliseconds: maximumLifetimeMilliseconds
            )
            phase = .operating
            continuation.yield(.established)
            startLiveness()
          } catch {
            #if DEBUG
              let errDesc = String(describing: error)
              Self.logger.notice(
                "[RappCoordinator] beginOperationDriver failed: \(errDesc, privacy: .public)"
              )
            #endif
            await finish(.handshake(.protocolFailure))
          }

        case .closed(let reason):
          #if DEBUG
            let reasonDesc = String(describing: reason)
            Self.logger.notice(
              "[RappCoordinator] handshake closed with reason: \(reasonDesc, privacy: .public)"
            )
          #endif
          await finish(.handshake(reason))
        }
      }
    }

    /// Tells the session's owner that this custodian answered or refused
    /// `operationID`: the engine sends the answer as a plain frame, so no
    /// command marks the operation's end on this side.
    internal func answered(_ operationID: RappOperationIdentifier) {
      guard phase == .operating else { return }
      continuation.yield(.answered(operationID: operationID))
    }

    internal func handleOperation(_ commands: [RappOperationDriver.Command]) async {
      for command in commands where phase == .operating || phase == .closingOperation {
        if let event = Event(command) {
          continuation.yield(event)
          continue
        }
        switch command {
        case .send(let frame, let release):
          await sendOperationFrame(frame, release: release)

        case .awaitCloseEcho:
          ownCloseLeft = true
          startEchoWait(.closingOperation)

        case .peerNamed(let name):
          continuation.yield(.peerNamed(name))

        case .closed(let reason):
          await finish(.operation(reason))

        default:
          break
        }
      }
    }

    private func sendOperationFrame(
      _ frame: Data,
      release: RappOperationDriver.FrameRelease
    ) async {
      do {
        try await transport.send(frame)
        guard let operation else {
          await finish(.transportFailure)
          return
        }
        await handleOperation(await operation.frameReleased(release, succeeded: true))
      } catch {
        if let operation { _ = await operation.transportClosed() }
        await finish(.transportFailure)
      }
    }

    /// Polls liveness and the live operation's deadline on a fixed cadence
    /// while the session operates.
    private func startLiveness() {
      livenessTask?.cancel()
      let interval = Self.livenessPollIntervalMilliseconds
      livenessTask = Task { [weak self] in
        while !Task.isCancelled {
          do {
            try await Task.sleep(for: .milliseconds(interval))
          } catch {
            return
          }
          guard let self else { return }
          await pollLiveness()
        }
      }
    }

    internal func finish(_ reason: CloseReason) async {
      guard phase != .closed else { return }
      phase = .closed
      closeReason = reason
      livenessTask?.cancel()
      livenessTask = nil
      echoTask?.cancel()
      echoTask = nil
      await transport.close()
      continuation.yield(.closed(reason))
      continuation.finish()
      let waiters = finishWaiters
      finishWaiters = []
      for waiter in waiters { waiter.resume() }
    }

    deinit {
      livenessTask?.cancel()
      echoTask?.cancel()
      continuation.finish()
    }
  }
#endif
