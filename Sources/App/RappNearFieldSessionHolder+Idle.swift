// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import Foundation

  /// What the holder does with a session between two requests.
  extension RappNearFieldSessionHolder {
    /// Looks at the idle slot between two keep-alive commands.
    ///
    /// The system takes the slot away some six seconds after the last
    /// exchange.
    internal static let keepAliveLooks: Int = 2

    /// Wait between two looks at the idle slot.
    internal static let idleWatchInterval: Duration = .seconds(1)

    /// Keeps or ends the hold after an operation, and arms the idle limit.
    ///
    /// No outcome means the channel was never prepared or the operation
    /// never ran: whatever the hold says, nothing is kept.
    internal func settle(outcome: RappCardExecutor.Outcome?) {
      guard let outcome else {
        end(hold.commandFailed())
        releaseEverything()
        return
      }
      let verdict = hold.operationFinished(
        answered: outcome.cardAnswered,
        nowMs: Self.nowMs()
      )
      guard case .keep = verdict, activeSession?.holdsValidCard == true else {
        end(verdict)
        releaseEverything()
        return
      }
      expirationTask = Task { [weak self] in
        await self?.watchIdle()
      }
    }

    /// Follows the card while the hold is idle, and keeps the field up.
    ///
    /// A slot that no longer reports a valid card ends the session at
    /// once: the reader's pause after a session then runs while nothing
    /// is asked of the card, instead of refusing the next request's
    /// fresh session. The idle limit ends the session otherwise. Between
    /// looks, one harmless command on the held channel keeps the system
    /// from taking the slot away, so a request that follows within the
    /// hold reuses the channel.
    private func watchIdle() async {
      var lastState = activeSession?.slotState.traceName
      var looks = 0
      while !Task.isCancelled {
        try? await Task.sleep(for: Self.idleWatchInterval)
        guard !Task.isCancelled else { return }
        looks += 1
        if looks.isMultiple(of: Self.keepAliveLooks) {
          guard await keptAlive() else {
            end(hold.commandFailed())
            releaseEverything()
            return
          }
          guard !Task.isCancelled else { return }
        }
        #if DEBUG
          let state = activeSession?.slotState.traceName
          if state != lastState {
            HolderTrace.say("watchIdle: slot state \(lastState ?? "nil") -> \(state ?? "nil")")
            lastState = state
          }
        #endif
        guard activeSession?.holdsValidCard == true else {
          end(hold.cardLeft())
          releaseEverything()
          return
        }
        let verdict = hold.tick(nowMs: Self.nowMs())
        guard case .end = verdict else { continue }
        end(verdict)
        releaseEverything()
        return
      }
    }

    /// Sends one harmless command on the held channel.
    ///
    /// Tells whether the card answered it. A request that arrives
    /// meanwhile waits for the answer before it uses the channel.
    private func keptAlive() async -> Bool {
      guard let held = heldChannel, hold.reusesChannel else { return true }
      let command = Task.detached(priority: .utility) {
        (try? held.operations.selectFineidApplication()) != nil
      }
      keepAlive = command
      let answered = await command.value
      keepAlive = nil
      return answered
    }
  }
#endif
