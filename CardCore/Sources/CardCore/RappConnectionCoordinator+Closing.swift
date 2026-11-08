// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// How a connection ends with a close of this endpoint's own, and the
  /// wait for its echo (RAPP v26.11.2 §7.1 item 7).
  extension RappConnectionCoordinator {
    /// Waits until the connection has closed.
    public func waitUntilClosed() async {
      guard phase != .closed else { return }
      await withCheckedContinuation { finishWaiters.append($0) }
    }

    /// The bound of the wait for the echo of this endpoint's close passed.
    internal func echoWaitEnded() async {
      switch phase {
      case .closingHandshake:
        await handleHandshake(await handshake.close())

      case .closingOperation:
        await handleOperation(await operation?.echoWaitEnded() ?? [])

      default:
        return
      }
    }

    /// Starts the wait for the echo of this endpoint's close, within its
    /// bound (§7.1 item 7); liveness stops.
    internal func startEchoWait(_ closing: Phase) {
      phase = closing
      livenessTask?.cancel()
      livenessTask = nil
      let bound = closeEchoBoundMilliseconds
      echoTask = Task { [weak self] in
        do {
          try await Task.sleep(for: .milliseconds(bound))
        } catch {
          return
        }
        await self?.echoWaitEnded()
      }
    }

    /// Ends the session with `pairing_revoked` because this endpoint's
    /// user is forgetting the pairing (RAPP v26.11.2 §4.6 item 1), and
    /// returns once the echo arrived or the wait for it ended (§7.1 item 7).
    ///
    /// Answers whether the close left on the transport. Only then may the
    /// record and its key be destroyed (§4.6 item 3); otherwise a custodian
    /// keeps the pairing forgotten so its next session delivers the close.
    public func closePairingRevoked() async -> Bool {
      await closeWithNotice(.pairingRevoked)
    }

    /// Ends the session with `pairing_revoked` as a requester's user forgets
    /// the pairing, and answers whether the custodian echoed it.
    ///
    /// Only the echo within the wait (RAPP v26.11.2 §7.1 item 7) lets a
    /// requester destroy the record and its key; without it the pairing
    /// stays forgotten in the revocation backlog (§4.6 item 6).
    public func closePairingRevokedAwaitingEcho() async -> Bool {
      guard await closePairingRevoked(), let operation else { return false }
      return await operation.ownCloseEchoed
    }

    /// Ends the session with `service_withdrawn` because this endpoint
    /// withdraws: its holder turned remote access off, a local card
    /// suspended remote use, or the holder quit (RAPP v26.11.2 §4.5 items 3
    /// and 8), and returns once the echo arrived or the wait for it ended.
    ///
    /// An open session sends the close before the connection goes; one not
    /// yet open closes without a notice. Answers whether the close left on
    /// the transport.
    @discardableResult
    public func closeServiceWithdrawn() async -> Bool {
      await closeWithNotice(.serviceWithdrawn)
    }

    /// Ends the session with `card_unavailable` because the custodian can
    /// no longer serve any card for the rest of it (§8.4 item 5); the
    /// pairing stays.
    public func closeCardUnavailable() async {
      await closeWithNotice(.cardUnavailable)
    }

    /// Sends this endpoint's close carrying `reason` on an open session and
    /// waits for the end of the connection; answers whether the close left.
    private func closeWithNotice(_ reason: RappCloseReason) async -> Bool {
      let wasOperating = phase == .operating
      await endOperating { await $0.close(reason: reason) }
      await waitUntilClosed()
      return wasOperating && ownCloseLeft
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

      case .closingHandshake, .closingOperation, .closed:
        return
      }
    }
  }
#endif
