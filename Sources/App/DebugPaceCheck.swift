// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG

  import CardCore
  import CryptoTokenKit
  import Foundation

  /// Runs one PACE handshake over an attached reader and times every step.
  ///
  /// This exists because the phone cannot answer the question it raises. A
  /// system NFC session is bounded, so a handshake that runs long is cut
  /// off part way and every measurement afterwards describes the wreckage
  /// rather than the handshake. A reader has no such bound: the card stays
  /// powered, PACE finishes however long it takes, and the timings are of
  /// the protocol rather than of a deadline.
  ///
  /// Finishing matters for its own sake too. MultiApp v5 deliberately
  /// delays CAN-PACE after unsuccessful attempts, and an interrupted run
  /// may be counted as another presentation. The public security target
  /// does not disclose the counter's reset rule; see
  /// `Documentation/bugs/2026-08-09-thales-can-pace-delay.md`.
  internal enum DebugPaceCheck {
    /// Carries a slot out of the manager's callback.
    ///
    /// `@unchecked Sendable` is sound because the semaphore below is the
    /// synchronisation: the write happens before the wait returns, and
    /// nothing else touches it.
    private final class SlotHolder: @unchecked Sendable {
      var slot: TKSmartCardSlot?
    }

    /// How many trace lines to print after the run.
    private static let tracedLines: Int = 12

    /// Names every slot, then runs the handshake on the first slot
    /// holding a card.
    internal static func perform() -> DebugModeReport {
      var lines = ["=== pace check ==="]
      guard let manager = TKSmartCardSlotManager.default else {
        return DebugModeReport(lines: lines + ["no slot manager"], succeeded: false)
      }
      let names = manager.slotNames
      lines.append("slots (\(names.count)):")
      // Named with what each one holds. A dual-interface reader
      // publishes its contact, contactless and SAM interfaces under one
      // name differing only by a trailing index, and the index does not
      // say which is which -- the answer to reset does. A contact FINEID
      // card opens `3B 7F`; a card on the antenna is reached through
      // T=CL, whose synthesized answer opens `3B 8x 80 01`.
      for name in names {
        let slot = Self.slot(named: name, in: manager)
        lines.append("  " + name)
        lines.append("      state=" + Self.description(of: slot?.state))
        lines.append("      atr=" + Self.hex(slot?.atr?.bytes))
      }
      guard let accessNumber = CardCredentialStore.cardAccessNumber() else {
        return DebugModeReport(
          lines: lines + ["no card access number stored; use --set-can first"],
          succeeded: false)
      }
      guard let (name, card) = Self.firstCard(in: manager, named: names) else {
        return DebugModeReport(
          lines: lines + ["no slot reported a card"], succeeded: false)
      }
      lines.append("using slot: " + name)
      return Self.run(on: card, accessNumber: accessNumber, lines: lines)
    }

    /// What a slot state is called, for the listing above.
    private static func description(of state: TKSmartCardSlot.State?) -> String {
      switch state {
      case .empty:
        "empty"

      case .missing:
        "missing"

      case .muteCard:
        "mute card"

      case .probing:
        "probing"

      case .validCard:
        "valid card"

      case nil:
        "no slot"

      @unknown default:
        "unknown"
      }
    }

    /// Bytes as spaced hex, or a dash.
    ///
    /// An answer to reset is public: it names the card's interface and
    /// carries no holder data.
    private static func hex(_ bytes: Data?) -> String {
      guard let bytes, !bytes.isEmpty else { return "-" }
      return bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// The first slot that has a card in it, with that card.
    private static func firstCard(
      in manager: TKSmartCardSlotManager,
      named names: [String]
    ) -> (String, TKSmartCard)? {
      for name in names {
        let slot = Self.slot(named: name, in: manager)
        guard let slot, slot.state == .validCard, let card = slot.makeSmartCard() else {
          continue
        }
        return (name, card)
      }
      return nil
    }

    /// Fetches one slot synchronously; the manager answers on a callback.
    private static func slot(
      named name: String,
      in manager: TKSmartCardSlotManager
    ) -> TKSmartCardSlot? {
      let holder = SlotHolder()
      let semaphore = DispatchSemaphore(value: 0)
      manager.getSlot(withName: name) { found in
        holder.slot = found
        semaphore.signal()
      }
      semaphore.wait()
      return holder.slot
    }

    /// Opens a session, selects main file, runs PACE, and reports.
    private static func run(
      on card: TKSmartCard,
      accessNumber: CardAccessNumber,
      lines: [String]
    ) -> DebugModeReport {
      var lines = lines
      let started = ContinuousClock.now
      do {
        try SmartCardChannel(card).withSession { channel in
          lines.append("session: open")
          // The same order the signature uses: main file first,
          // because the card refuses MSE:Set AT anywhere else.
          try? CardOperations(channel: channel).selectMainFile()
          _ = try PaceEstablishment(channel: channel).establish(
            with: PacePassword(cardAccessNumber: accessNumber))
        }
      } catch {
        lines.append(
          "pace FAILED after "
            + TraceTiming.milliseconds(started.duration(to: ContinuousClock.now))
            + " ms: \(error)")
        lines.append(contentsOf: ExtensionTrace.read().suffix(Self.tracedLines))
        return DebugModeReport(lines: lines, succeeded: false)
      }
      lines.append(
        "pace OK in "
          + TraceTiming.milliseconds(started.duration(to: ContinuousClock.now)) + " ms")
      lines.append(contentsOf: ExtensionTrace.read().suffix(Self.tracedLines))
      return DebugModeReport(lines: lines, succeeded: true)
    }
  }

#endif
