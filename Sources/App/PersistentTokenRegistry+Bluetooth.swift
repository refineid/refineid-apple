// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if (os(macOS) || os(iOS)) && REFINEID_STREAM_TRANSPORT
  import CardCore
  import Foundation
  import RappEngine

  /// The registry's Bluetooth half, and the operations the token extension
  /// hands over (CC-71).
  extension PersistentTokenRegistry {
    /// How often a handed-over operation looks again for a session it can
    /// run on while none is up.
    private static let carryPollMilliseconds = 250

    /// The failure a requester reports for an operation the held session
    /// could not answer.
    private static func clientError(
      _ error: any Error
    ) -> RappRequesterClientError {
      switch error as? RappHeldRequesterSession.OperationError {
      case .terminal(let reason):
        .terminal(reason)

      case .unexpectedResult:
        .unexpectedResult

      case .notEstablished, .closed, nil:
        .transport
      }
    }

    /// Carries an operation the token extension handed over (CC-71).
    ///
    /// This computer holds one session with the phone, and the app holds
    /// it, over either transport: the operation runs on it, after any
    /// operation already running there. With none open the app dials one,
    /// within the dial's back-off, and waits for it within the handoff's
    /// window; a session over another pairing, one being forgotten, is
    /// waited out. While remote use is off or a card is in this computer's
    /// reader, the operation is refused (CC-94, CC-86).
    internal func carry(
      _ request: RappHeldSessionHandoff.Request
    ) async -> RappHeldSessionHandoff.Answer {
      guard Self.followsPhone else {
        #if DEBUG
          DevErrorLog.report("handed-over operation refused: remote use is off", source: .app)
        #endif
        return .failed(.peerNotFound)
      }
      guard !CardPresence.shared.isReaderCardPresent else {
        #if DEBUG
          DevErrorLog.report(
            "handed-over operation refused: a local card overrides the phone", source: .app)
        #endif
        return .failed(.peerNotFound)
      }
      let deadline = ContinuousClock.now + .seconds(RappHeldSessionHandoff.establishWaitSeconds)
      let poll = Duration.milliseconds(Self.carryPollMilliseconds)
      while ContinuousClock.now < deadline {
        openHolderSession()
        if let session = holderSession, request.pairID == nil || request.pairID == session.pairID,
          await session.established(within: deadline - .now)
        {
          #if DEBUG
            print("[persistent-token] carrying the extension's operation")
            fflush(stdout)
          #endif
          return await perform(request.operation, on: session)
        }
        try? await Task.sleep(for: min(poll, deadline - .now))
      }
      return .failed(.peerNotFound)
    }

    /// Runs `operation` for this app on the computer's one session with the
    /// phone, as a handed-over operation runs (CC-71), and answers what the
    /// phone answered.
    internal func perform(_ operation: RappRequesterOperation) async throws
      -> RappRequesterResponse
    {
      switch await carry(RappHeldSessionHandoff.Request(pairID: nil, operation: operation)) {
      case .response(let response):
        return response

      case .failed(let error):
        throw error
      }
    }

    /// Runs a handed-over operation on `session` and answers its outcome.
    private func perform(
      _ operation: RappRequesterOperation, on session: RappHeldRequesterSession
    ) async -> RappHeldSessionHandoff.Answer {
      do {
        return .response(try await session.perform(operation))
      } catch {
        #if DEBUG
          DevErrorLog.report(
            "handed-over operation failed: \(DevErrorLog.reason(error))", source: .app)
        #endif
        return .failed(Self.clientError(error))
      }
    }

    /// Follows the Bluetooth link's steps: Bluetooth found off or refused
    /// stops the Bluetooth dials until the phone's presence or the pairing
    /// changes; in a development build every step goes to the console and
    /// every failure to the error strip.
    internal func bluetoothStep(_ step: RappBleGattTrace) {
      if step == .ended(.bluetoothUnavailable) {
        bluetoothUsable = false
      }
      #if DEBUG
        print("[persistent-token] ble \(step.line)")
        fflush(stdout)
        AppTrace.append("[persistent-token] ble \(step.line)")
        switch step {
        case .ended(let failure) where failure != .cancelled && failure != .disconnected:
          DevErrorLog.report("phone over Bluetooth: \(step.line)", source: .app)

        case .connected(_, let attMtu) where attMtu < RappBleSar.minimumAttMtu:
          DevErrorLog.report("phone over Bluetooth: ATT MTU \(attMtu) too small", source: .app)

        default:
          break
        }
      #endif
    }
  }
#endif
