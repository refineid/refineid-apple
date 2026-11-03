// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import OSLog
  import RappEngine
  /// Transport-independent coordinator for the authenticated RAPP session setup
  /// (RAPP v26.11.2 §6.3, §7.1 items 5 to 7).
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
      /// The handshake failed, or a frame failed authentication: a loss.
      case protocolFailure
      /// This endpoint detected an authenticated protocol violation and
      /// closed with `protocol_violation`; the pairing stays (§10.1).
      case protocolViolation
      /// The peer revoked the pairing; revoke it here too and withdraw its
      /// identity (§4.6 item 4).
      case pairRevoked
      /// This endpoint's pairing was forgotten and the session carried the
      /// `pairing_revoked` close as its only message, echoed or not within
      /// the wait; destroy the record now (§4.6 items 2 and 3, §7.1 item 7).
      case revocationNoticeDelivered
      /// The custodian closed the session in place of `session.ready` with
      /// another registered reason.
      case peerClosed(RappCloseReason)
    }

    /// An effect the caller must apply, in array order, after a driver call.
    public enum Command: Sendable, Equatable {
      /// Deliver these opaque bytes to the selected transport peer.
      case send(Data)
      /// The peer named itself (§4.3 item 4): `session.ready` on the
      /// requester. Record the name in the pair record where it differs.
      case peerNamed(RappDisplayName)
      /// The handshake and `session.ready` have completed.
      case established
      /// This endpoint sent its close; keep the link and feed frames until
      /// the echo arrives, or end the wait with ``close()`` once its bound
      /// passed (§7.1 item 7).
      case awaitCloseEcho
      /// Tear down the physical transport and discard the session driver.
      case closed(CloseReason)
    }

    private enum State: Equatable {
      case idle
      case awaitingRequesterHandshake
      case awaitingResponderHandshake
      case awaitingCustodianReady
      /// This endpoint's close was sent; the reason the session ends with.
      case awaitingEcho(CloseReason)
      case established
      case operationsTransferred
      case closed
    }

    private static let logger = Logger(subsystem: "fi.refineid.ReFineID", category: "rapp-session")

    private let role: Role
    private let displayName: RappDisplayName
    private let session: RappSessionBridge
    private let entropy: RappPlatformEntropy
    private let clock: RappPlatformClock
    private var state = State.idle

    /// Binds a new driver to one pair and opens the role's side of the
    /// session bridge, bound to the connection's transport profile.
    /// `displayName` is this endpoint's current name, sent in
    /// `session.ready` or `session.hello` (§4.3 item 4).
    public init(
      role: Role,
      pair: RappPairRecord,
      displayName: RappDisplayName,
      transportProfile: String = rappStreamProfileName(),
      entropy: RappPlatformEntropy = RappPlatformEntropy(),
      clock: RappPlatformClock = RappPlatformClock()
    ) throws {
      self.role = role
      self.displayName = displayName
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

        case .awaitingEcho(let reason):
          return receiveCloseEcho(frame, expecting: reason)

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

    /// Answers one frame while waiting for the echo of the sent close:
    /// anything but the echo is ignored, and a crossing close that
    /// revokes the pairing is acted on.
    private func receiveCloseEcho(_ frame: Data, expecting reason: CloseReason) -> [Command] {
      switch session.receiveCloseEcho(bytes: frame) {
      case .ignored:
        return []

      case .acknowledged(.pairingRevoked) where reason != .revocationNoticeDelivered:
        // A crossing close that revokes the pairing is acted on.
        closeSession()
        return [.closed(.pairRevoked)]

      case .acknowledged, .ended:
        closeSession()
        return [.closed(reason)]
      }
    }

    /// Closes the session because the transport closed underneath it.
    public func transportClosed() -> [Command] {
      guard state != .closed else {
        return []
      }
      return ending(as: .transportClosed)
    }

    /// Closes the session at the owner's request; while this endpoint waits
    /// for the echo of its close, it ends the wait.
    public func close() -> [Command] {
      guard state != .closed else {
        return []
      }
      return ending(as: .localRequest)
    }

    /// Ends the session; a sent close names the end whatever cut the wait.
    private func ending(as reason: CloseReason) -> [Command] {
      let ended: CloseReason
      if case .awaitingEcho(let sent) = state {
        ended = sent
      } else {
        ended = reason
      }
      closeSession()
      return [.closed(ended)]
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
      let ready = try session.sendReady(
        nonce: entropy.sessionReadyNonce(), displayName: displayName)
      try session.enterEstablished()
      state = .established
      return [.send(response), .send(ready), .established]
    }

    /// The requester reads the custodian's first message.
    private func readCustodianReady(_ frame: Data) throws -> [Command] {
      switch try session.receiveReady(bytes: frame, displayName: displayName) {
      case .verified(let peerName, let hello):
        try session.enterEstablished()
        state = .established
        return [.peerNamed(peerName), .send(hello), .established]

      case .peerClosed(let reason, let echo):
        closeSession()
        return (echo.map { [Command.send($0)] } ?? [])
          + [.closed(reason == .pairingRevoked ? .pairRevoked : .peerClosed(reason))]

      case .violationClosed(let notice?):
        state = .awaitingEcho(.protocolViolation)
        return [.send(notice), .awaitCloseEcho]

      case .violationClosed(nil):
        closeSession()
        return [.closed(.protocolViolation)]

      case .integrityFailure:
        return failClosed()
      }
    }

    /// The close a forgotten record owes its peer, as the session's only
    /// message; the wait for its echo follows (§7.1 item 7).
    private func deliverRevocationNotice(after preceding: [Command]) -> [Command] {
      guard let notice = try? session.deliverRevocationNotice() else {
        return preceding + failClosed()
      }
      state = .awaitingEcho(.revocationNoticeDelivered)
      return preceding + [.send(notice), .awaitCloseEcho]
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
