// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import OSLog
  import RappEngine

  /// Runs one authenticated connection from Noise setup through card
  /// operations. All externally visible events are semantic and authenticated.
  public actor RappConnectionCoordinator {
    private enum Phase: Equatable {
      case handshaking
      case operating
      case closed
    }

    /// How often a session advances its liveness and checks the live
    /// operation's deadline; the engine decides when a ping is due (RAPP
    /// v26.10.21 §8.1 item 2, §8.3).
    public static let livenessPollIntervalMilliseconds: UInt64 = 1_000

    private static let logger = Logger(
      subsystem: "fi.refineid.ReFineID", category: "rapp-coordinator"
    )

    // MARK: Properties

    /// Connection events in order; the stream finishes after `closed`.
    nonisolated public let events: AsyncStream<Event>

    private let transport: any RappFrameTransport
    private let handshake: RappSessionDriver
    private let maximumLifetimeMilliseconds: UInt64
    private let continuation: AsyncStream<Event>.Continuation
    private var operation: RappOperationDriver?
    private var phase = Phase.handshaking
    private var livenessTask: Task<Void, Never>?

    // MARK: Lifecycle

    /// Prepares one connection over an established pair; ``start()`` sends
    /// the first frame. `transportProfile` names the transport the
    /// connection runs over, which the Noise prologue binds.
    public init(
      role: RappSessionDriver.Role,
      pair: RappPairRecord,
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
      case .handshaking:
        await handleHandshake(await handshake.receive(frame))

      case .operating:
        guard let operation else {
          await finish(.transportFailure)
          return
        }
        await handleOperation(await operation.receive(frame))

      case .closed:
        return
      }
    }

    /// Runs one liveness poll and deadline check.
    public func pollLiveness() async {
      guard phase == .operating, let operation else { return }
      await handleOperation(await operation.expireDue())
      guard phase == .operating else { return }
      await handleOperation(await operation.pollLiveness())
    }

    /// Reports that the transport closed without a local request.
    public func transportClosed() async {
      switch phase {
      case .handshaking:
        await handleHandshake(await handshake.transportClosed())

      case .operating:
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

    private func handleHandshake(_ commands: [RappSessionDriver.Command]) async {
      for command in commands where phase == .handshaking {
        switch command {
        case .send(let frame):
          do {
            try await transport.send(frame)
          } catch {
            _ = await handshake.transportClosed()
            await finish(.transportFailure)
          }

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

    internal func handleOperation(_ commands: [RappOperationDriver.Command]) async {
      for command in commands where phase == .operating {
        if let event = Event(command) {
          continuation.yield(event)
          continue
        }
        switch command {
        case .send(let frame, let release):
          await sendOperationFrame(frame, release: release)

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

    /// Ends the session with `pairing_revoked` because this endpoint's
    /// user is forgetting the pairing (RAPP v26.10.21 §4.6 item 1).
    public func closePairingRevoked() async {
      await endOperating { await $0.close(reason: .pairingRevoked) }
    }

    /// Ends the session with `service_withdrawn` because the holder
    /// stopped serving (RAPP v26.10.21 §4.5).
    public func closeServiceWithdrawn() async {
      await endOperating { await $0.close(reason: .serviceWithdrawn) }
    }

    /// Ends the session with `card_unavailable` because the custodian can
    /// no longer serve any card for the rest of it (§8.4 item 5); the
    /// pairing stays.
    public func closeCardUnavailable() async {
      await endOperating { await $0.close(reason: .cardUnavailable) }
    }

    /// Runs `ending` on the operation driver, or closes a session that
    /// never reached one.
    private func endOperating(
      _ ending: (RappOperationDriver) async -> [RappOperationDriver.Command]
    ) async {
      switch phase {
      case .handshaking:
        _ = await handshake.close()
        await finish(.localRequest)

      case .operating:
        guard let operation else {
          await finish(.localRequest)
          return
        }
        await handleOperation(await ending(operation))

      case .closed:
        return
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

    private func finish(_ reason: CloseReason) async {
      guard phase != .closed else { return }
      phase = .closed
      livenessTask?.cancel()
      livenessTask = nil
      await transport.close()
      continuation.yield(.closed(reason))
      continuation.finish()
    }

    deinit {
      livenessTask?.cancel()
      continuation.finish()
    }
  }
#endif
