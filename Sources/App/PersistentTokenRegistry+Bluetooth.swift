// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if (os(macOS) || os(iOS)) && REFINEID_STREAM_TRANSPORT
  import CardCore
  import Foundation
  import RappEngine

  /// The registry's Bluetooth half: the operations the token extension
  /// hands over (CC-71), and the Bluetooth link's steps.
  extension PersistentTokenRegistry {
    /// The failure a requester reports for an operation the held session
    /// could not answer.
    private static func clientError(
      _ error: any Error
    ) -> RappRequesterClientError {
      switch error as? RappHeldRequesterSession.OperationError {
      case .terminal(let reason):
        .terminal(reason)

      case .operationInFlight:
        .terminal(.busy)

      case .unexpectedResult:
        .unexpectedResult

      case .notEstablished, .closed, nil:
        .transport
      }
    }

    /// Carries an operation the token extension handed over (CC-71).
    ///
    /// Over Bluetooth only this app holds a link to the phone, so the app
    /// runs the operation on its session, dialing one and waiting for it
    /// within the handoff's window when none is open. Otherwise the
    /// extension dials the stream itself, as it does without this app.
    internal func carry(
      _ request: RappHeldSessionHandoff.Request
    ) async -> RappHeldSessionHandoff.Answer {
      guard Self.dialsPhones, !CardPresence.shared.isReaderCardPresent else { return .dialStream }
      let deadline = ContinuousClock.now + .seconds(RappHeldSessionHandoff.establishWaitSeconds)
      while ContinuousClock.now < deadline {
        guard transportPolicy.handoffCarrier(held: heldTransport) == .app else {
          return .dialStream
        }
        if let pairID = request.pairID, let held = holderSession, held.pairID != pairID {
          return .dialStream
        }
        if holderSession == nil {
          redialTask?.cancel()
          redialTask = nil
          openHolderSession()
        }
        guard let session = holderSession else { return .failed(.peerNotFound) }
        if await session.established(within: deadline - .now) {
          #if DEBUG
            print("[persistent-token] carrying the extension's operation over Bluetooth")
            fflush(stdout)
          #endif
          do {
            return .response(try await session.perform(request.operation))
          } catch {
            #if DEBUG
              DevErrorLog.report(
                "handed-over operation failed: \(DevErrorLog.reason(error))", source: .app)
            #endif
            return .failed(Self.clientError(error))
          }
        }
        try? await Task.sleep(for: Self.redialDelay)
      }
      return .failed(.peerNotFound)
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
