// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import OSLog
  import RappEngine
  /// Transport-independent coordinator for the authenticated RAPP session setup
  /// (RAPP v26.10.29 §6.3, §7.1 item 5).
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
      /// The peer revoked the pairing; revoke it here too and withdraw its
      /// identity (§4.6 item 4).
      case pairRevoked
      /// This endpoint's pairing was forgotten and the session carried the
      /// `pairing_revoked` close as its only message; destroy the record
      /// now (§4.6 items 2 and 3).
      case revocationNoticeDelivered
      /// The custodian closed the session in place of `session.ready` with
      /// another registered reason.
      case peerClosed(RappCloseReason)
    }

    /// An effect the caller must apply, in array order, after a driver call.
    public enum Command: Sendable, Equatable {
      /// Deliver these opaque bytes to the selected transport peer.
      case send(Data)
      /// The handshake and `session.ready` have completed.
      case established
      /// Tear down the physical transport and discard the session driver.
      case closed(CloseReason)
    }

    private enum State: Equatable {
      case idle
      case awaitingRequesterHandshake
      case awaitingResponderHandshake
      case awaitingCustodianReady
      case established
      case operationsTransferred
      case closed
    }

    private static let logger = Logger(subsystem: "fi.refineid.ReFineID", category: "rapp-session")

    private let role: Role
    private let session: RappSessionBridge
    private let entropy: RappPlatformEntropy
    private let clock: RappPlatformClock
    private var state = State.idle

    /// Binds a new driver to one pair and opens the role's side of the
    /// session bridge, bound to the connection's transport profile.
    public init(
      role: Role,
      pair: RappPairRecord,
      transportProfile: String = rappStreamProfileName(),
      entropy: RappPlatformEntropy = RappPlatformEntropy(),
      clock: RappPlatformClock = RappPlatformClock()
    ) throws {
      self.role = role
      self.entropy = entropy
      self.clock = clock

      switch role {
      case .requester:
        self.session = try RappSessionBridge.beginRequester(
          pair: pair, transportProfile: transportProfile)

      case .proxy:
        self.session = try RappSessionBridge.beginProxy(
          pair: pair, transportProfile: transportProfile)
      }
    }

    /// Starts a fresh session.
    ///
    /// The requester emits the first Noise KK frame; the custodian waits for
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
          return try answerHandshake(frame)

        case .awaitingResponderHandshake:
          try session.readHandshakeFrame(bytes: frame)
          guard try session.handshakeComplete() else {
            return failClosed()
          }
          try session.enterAuthentication()
          if session.revocationNoticePending() {
            return deliverRevocationNotice(after: [])
          }
          state = .awaitingCustodianReady
          return []

        case .awaitingCustodianReady:
          return try readCustodianReady(frame)

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

    /// Transfers the established Noise session into the operation runtime.
    ///
    /// After this succeeds, all received frames belong to the returned
    /// driver and this handshake driver must be discarded.
    public func beginOperationDriver(
      maximumLifetimeMilliseconds: UInt64
    ) throws -> RappOperationDriver {
      guard state == .established, session.isEstablished() else {
        throw RappOperationDriver.LocalError.wrongPhase
      }
      let driver = try RappOperationDriver(
        role: role,
        session: session,
        maximumLifetimeMilliseconds: maximumLifetimeMilliseconds,
        entropy: entropy,
        clock: clock
      )
      state = .operationsTransferred
      return driver
    }

    /// The custodian answers the requester's first handshake message: the
    /// second, then `session.ready`, or the `pairing_revoked` close in its
    /// place for a forgotten record.
    private func answerHandshake(_ frame: Data) throws -> [Command] {
      try session.readHandshakeFrame(bytes: frame)
      let response = try session.writeHandshakeFrame()
      guard try session.handshakeComplete() else {
        return failClosed()
      }
      try session.enterAuthentication()
      if session.revocationNoticePending() {
        return deliverRevocationNotice(after: [.send(response)])
      }
      let ready = try session.sendReady(nonce: entropy.sessionReadyNonce())
      try session.enterEstablished()
      state = .established
      return [.send(response), .send(ready), .established]
    }

    /// The requester reads the custodian's first message.
    private func readCustodianReady(_ frame: Data) throws -> [Command] {
      switch try session.receiveReady(bytes: frame) {
      case .verified:
        try session.enterEstablished()
        state = .established
        return [.established]

      case .peerClosed(let reason):
        closeSession()
        return [.closed(reason == .pairingRevoked ? .pairRevoked : .peerClosed(reason))]

      case .violationClosed(let notice):
        closeSession()
        return (notice.map { [Command.send($0)] } ?? []) + [.closed(.protocolFailure)]

      case .integrityFailure:
        return failClosed()
      }
    }

    /// The close a forgotten record owes its peer, as the session's only
    /// message.
    private func deliverRevocationNotice(after preceding: [Command]) -> [Command] {
      guard let notice = try? session.deliverRevocationNotice() else {
        return preceding + failClosed()
      }
      closeSession()
      return preceding + [.send(notice), .closed(.revocationNoticeDelivered)]
    }

    private func failClosed() -> [Command] {
      closeSession()
      return [.closed(.protocolFailure)]
    }

    private func closeSession() {
      if state != .closed {
        session.closeSession()
        state = .closed
      }
    }
  }
#endif
