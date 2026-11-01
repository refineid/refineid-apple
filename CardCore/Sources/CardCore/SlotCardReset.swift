// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CryptoTokenKit
  import Foundation
  import os.log
  import PcscCardReset

  /// Resets a present card at PC/SC level, which makes the system
  /// re-evaluate what the card is.
  ///
  /// `ctkd` remembers "no driver can handle this card" for as long as
  /// the card sits still, so a number offered after a failed mint
  /// changes nothing until the card arrives again. Lifting the card
  /// and laying it back is the physical version of this call; the
  /// reset is the same state change in software, and the
  /// re-evaluation that follows is what reads the fresh offer.
  public enum SlotCardReset {
    #if DEBUG
      /// Reset outcomes, in development builds only.
      ///
      /// Reader names and PC/SC statuses, never a digit. A
      /// production build writes no diagnostics.
      private static let log = Logger(
        subsystem: "fi.refineid.ReFineID", category: "card-reset"
      )
    #endif

    /// Resets the card in one named slot, and answers whether the reset
    /// went through.
    ///
    /// For a card whose state the app just changed and no longer uses:
    /// the system reads it again and publishes what it now is.
    public static func resetCard(slotNamed name: String) -> Bool {
      guard
        let manager = TKSmartCardSlotManager.default,
        let slot = manager.slotNamed(name),
        slot.state == .validCard
      else { return false }
      let status = CardCoreResetCard(name)
      #if DEBUG
        Self.log.error(
          "reset \(name, privacy: .public): status \(String(format: "0x%08X", status), privacy: .public)"
        )
      #endif
      return status == 0
    }

    /// Resets every present card on a contactless interface, and
    /// answers whether at least one reset went through.
    ///
    /// Contactless only: this is called for a sealed card the system
    /// has given up on, and a card something is using must never be
    /// reset under it.
    public static func resetContactlessCards() -> Bool {
      guard let manager = TKSmartCardSlotManager.default else { return false }
      var anyReset = false
      for name in manager.slotNames {
        guard
          let slot = manager.slotNamed(name),
          slot.state == .validCard,
          let answer = slot.atr?.bytes,
          AnswerToReset.indicatesContactlessInterface(bytes: answer)
        else { continue }
        let status = CardCoreResetCard(name)
        #if DEBUG
          Self.log.error(
            "reset \(name, privacy: .public): status \(String(format: "0x%08X", status), privacy: .public)"
          )
        #endif
        if status == 0 {
          anyReset = true
        }
      }
      return anyReset
    }
  }

#endif
