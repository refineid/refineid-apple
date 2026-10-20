// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import OSLog
  import RappEngine

  /// Runs one authenticated connection from Noise setup through durable card
  /// operations. All externally visible events are semantic and authenticated.
  public actor RappConnectionCoordinator {
    private enum Phase: Equatable {
      case handshaking
      case operating
      case closed
    }

    private static let logger = Logger(
      subsystem: "fi.refineid.ReFineID", category: "rapp-coordinator"
    )

    // MARK: Properties

    /// Connection events in order; the stream finishes after `closed`.
    nonisolated public let events: AsyncStream<Event>

    private let transport: any RappFrameTransport
    private let handshake: RappSessionDriver
    private let maximumLifetimeMilliseconds: UInt64
    private let liveness: RappOperationDriver.Liveness
    private let clock: RappPlatformClock
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
      vault: RappDeviceVault,
      transport: any RappFrameTransport,
      maximumLifetimeMilliseconds: UInt64,
      liveness: RappOperationDriver.Liveness,
      transportProfile: String = rappStreamProfileName(),
      clock: RappPlatformClock = RappPlatformClock()
    ) throws {
      self.transport = transport
      self.maximumLifetimeMilliseconds = maximumLifetimeMilliseconds
      self.liveness = liveness
      self.clock = clock
      self.handshake = try RappSessionDriver(
        role: role,
        pair: pair,
        vault: vault,
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

    /// Runs one liveness poll with the given scheduling jitter.
    public func pollLiveness(jitterMilliseconds: Int64) async {
      guard phase == .operating, let operation else { return }
      await handleOperation(
        await operation.pollLiveness(
          jitterMilliseconds: jitterMilliseconds
        ))
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

    /// Closes the connection and finishes the event stream.
    public func close() async {
      switch phase {
      case .handshaking:
        _ = await handshake.close()

      case .operating:
        if let operation { _ = await operation.close() }

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
              maximumLifetimeMilliseconds: maximumLifetimeMilliseconds,
              liveness: liveness
            )
            phase = .operating
            continuation.yield(.established)
            let now = clock.monotonicMilliseconds()
            let (deadline, overflow) = now.addingReportingOverflow(
              liveness.baseIntervalMilliseconds
            )
            scheduleLiveness(at: overflow ? UInt64.max : deadline)
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

        case .scheduleLiveness(let deadline):
          scheduleLiveness(at: deadline)

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
    /// user is forgetting the pairing (RAPP v26.10.18 §4.6 item 1).
    public func closePairingRevoked() async {
      await endOperating { await $0.close(reason: .pairingRevoked) }
    }

    /// Ends the session with `service_withdrawn` because the holder
    /// stopped serving (RAPP v26.10.18 §4.5).
    public func closeServiceWithdrawn() async {
      await endOperating { await $0.close(reason: .serviceWithdrawn) }
    }

    /// Ends the session and the pairing because the card can no longer
    /// be served.
    public func revokeBecauseCardUnavailable() async {
      await endOperating { await $0.revokeBecauseCardUnavailable() }
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

    private func scheduleLiveness(at deadline: UInt64) {
      guard phase == .operating else { return }
      livenessTask?.cancel()

      let now = clock.monotonicMilliseconds()
      enum Timing {
        static let nanosecondsPerMillisecond: UInt64 = 1_000_000
      }

      let delayMilliseconds = deadline > now ? deadline - now : 0
      let maximumDelayNanoseconds = UInt64.max
      let (convertedDelay, overflow) = delayMilliseconds.multipliedReportingOverflow(
        by: Timing.nanosecondsPerMillisecond
      )
      let delayNanoseconds = overflow ? maximumDelayNanoseconds : convertedDelay
      let maximumJitter = min(
        liveness.maximumJitterMilliseconds,
        UInt64(Int64.max)
      )

      livenessTask = Task { [weak self] in
        do {
          try await Task.sleep(nanoseconds: delayNanoseconds)
        } catch {
          return
        }
        guard !Task.isCancelled, let self else { return }

        var generator = SystemRandomNumberGenerator()
        let bound = Int64(maximumJitter)
        let jitter = Int64.random(in: -bound...bound, using: &generator)
        await pollLiveness(jitterMilliseconds: jitter)
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
