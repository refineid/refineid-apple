// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import OSLog
  import RappEngine
  /// Transport-independent coordinator for the authenticated RAPP session setup.
  ///
  /// The surrounding transport may carry bytes and report closure, but it must not
  /// interpret RAPP frames or decide protocol state. Card operations may start only
  /// after this driver emits ``Command/established``.
  public actor RappSessionDriver {
    /// Which side of the pair this driver speaks for.
    public enum Role: Sendable {
      case requester
      case proxy
    }

    /// Why the driver closed the session.
    public enum CloseReason: Sendable, Equatable {
      case localRequest
      case transportClosed
      case protocolFailure
      case pairRevoked
    }

    /// An effect the caller must apply, in array order, after a driver call.
    public enum Command: Sendable, Equatable {
      /// Deliver these opaque bytes to the selected transport peer.
      case send(Data)
      /// Noise KK and mutual authenticated readiness have completed.
      case established
      /// Tear down the physical transport and discard the session driver.
      case closed(CloseReason)
    }

    private enum State: Equatable {
      case idle
      case awaitingRequesterHandshake
      case awaitingResponderHandshake
      case awaitingRequesterReady
      case awaitingResponderReady
      case established
      case operationsTransferred
      case closed
    }

    private static let logger = Logger(subsystem: "fi.refineid.ReFineID", category: "rapp-session")

    private let role: Role
    private let pairID: Data
    private let vault: RappDeviceVault
    private let session: RappSessionBridge
    private let entropy: RappPlatformEntropy
    private let clock: RappPlatformClock
    private var state = State.idle

    /// Binds a new driver to one pair and opens the role's side of the
    /// session bridge, bound to the connection's transport profile.
    public init(
      role: Role,
      pair: RappPairRecord,
      vault: RappDeviceVault,
      transportProfile: String = rappStreamProfileName(),
      entropy: RappPlatformEntropy = RappPlatformEntropy(),
      clock: RappPlatformClock = RappPlatformClock()
    ) throws {
      self.role = role
      self.pairID = pair.metadata().pairId
      self.vault = vault
      self.entropy = entropy
      self.clock = clock

      switch role {
      case .requester:
        self.session = try RappSessionBridge.beginRequester(
          pair: pair, vault: vault, transportProfile: transportProfile)

      case .proxy:
        self.session = try RappSessionBridge.beginProxy(
          pair: pair, vault: vault, transportProfile: transportProfile)
      }
    }

    /// Starts a fresh session.
    ///
    /// The requester emits the first Noise KK frame; the proxy waits for
    /// it. Reusing a driver is a protocol error.
    public func start() -> [Command] {
      guard state == .idle else {
        return failClosed()
      }

      do {
        switch role {
        case .requester:
          let frame = try session.writeHandshakeFrame()
          state = .awaitingResponderHandshake
          return [.send(frame)]

        case .proxy:
          state = .awaitingRequesterHandshake
          return []
        }
      } catch {
        #if DEBUG
          let errDesc = String(describing: error)
          Self.logger.notice("[RappSessionDriver] start failed: \(errDesc, privacy: .public)")
        #endif
        return failClosed()
      }
    }

    /// Consumes one complete opaque frame received from the selected peer.
    public func receive(_ frame: Data) -> [Command] {
      do {
        switch state {
        case .awaitingRequesterHandshake:
          try session.readHandshakeFrame(bytes: frame)
          let response = try session.writeHandshakeFrame()
          guard try session.handshakeComplete() else {
            return failClosed()
          }
          try session.enterAuthentication()
          state = .awaitingRequesterReady
          return [.send(response)]

        case .awaitingResponderHandshake:
          try session.readHandshakeFrame(bytes: frame)
          guard try session.handshakeComplete() else {
            return failClosed()
          }
          try session.enterAuthentication()
          let ready = try session.sendReady(nonce: entropy.sessionReadyNonce())
          state = .awaitingResponderReady
          return [.send(ready)]

        case .awaitingRequesterReady:
          try session.receiveReady(bytes: frame, nowMs: clock.wallMilliseconds())
          let ready = try session.sendReady(nonce: entropy.sessionReadyNonce())
          try session.enterEstablished()
          state = .established
          return [.send(ready), .established]

        case .awaitingResponderReady:
          try session.receiveReady(bytes: frame, nowMs: clock.wallMilliseconds())
          try session.enterEstablished()
          state = .established
          return [.established]

        case .idle, .established, .operationsTransferred, .closed:
          #if DEBUG
            let stateDesc = String(describing: self.state)
            Self.logger.notice(
              "[RappSessionDriver] receive in invalid state: \(stateDesc, privacy: .public)"
            )
          #endif
          return failClosed()
        }
      } catch {
        #if DEBUG
          let errDesc = String(describing: error)
          Self.logger.notice("[RappSessionDriver] receive failed: \(errDesc, privacy: .public)")
        #endif
        return failClosed()
      }
    }

    /// Closes the session because the transport closed underneath it.
    public func transportClosed() -> [Command] {
      guard state != .closed else {
        return []
      }
      closeSession()
      return [.closed(.transportClosed)]
    }

    /// Closes the session at the owner's request.
    public func close() -> [Command] {
      guard state != .closed else {
        return []
      }
      closeSession()
      return [.closed(.localRequest)]
    }

    /// Whether both this driver and the underlying session are established.
    public func isEstablished() -> Bool {
      state == .established && session.isEstablished()
    }

    /// Transfers the established Noise session into the durable operation
    /// runtime.
    ///
    /// After this succeeds, all received frames belong to the returned
    /// driver and this handshake driver must be discarded.
    public func beginOperationDriver(
      maximumLifetimeMilliseconds: UInt64,
      liveness: RappOperationDriver.Liveness
    ) throws -> RappOperationDriver {
      guard state == .established, session.isEstablished() else {
        throw RappOperationDriver.LocalError.wrongPhase
      }
      let driver = try RappOperationDriver(
        role: role,
        pairID: pairID,
        session: session,
        vault: vault,
        maximumLifetimeMilliseconds: maximumLifetimeMilliseconds,
        liveness: liveness,
        entropy: entropy,
        clock: clock
      )
      state = .operationsTransferred
      return driver
    }

    private func failClosed() -> [Command] {
      let pairWasRevoked = (try? vault.isRevoked(pairId: pairID)) == true
      closeSession()
      return [.closed(pairWasRevoked ? .pairRevoked : .protocolFailure)]
    }

    private func closeSession() {
      if state != .closed {
        session.closeSession()
        state = .closed
      }
    }
  }
#endif
