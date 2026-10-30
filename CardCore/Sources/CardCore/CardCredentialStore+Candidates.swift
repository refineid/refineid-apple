// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension CardCredentialStore {
  /// Every stored number to try, active offer first.
  ///
  /// A card answers with no individual identifier before PACE, so one
  /// stored number cannot be selected for it: the driver tries each in
  /// turn until one mints.
  public static func cardAccessNumberCandidates() -> [CardCanOffer.Candidate] {
    #if os(macOS)
      var strings: [String] = []
      if let stored = read(account: cardAccessNumberAccount) {
        strings.append(stored)
      }
      for candidate in CardCanOffer.candidates()
      where !strings.contains(candidate.digits) {
        strings.append(candidate.digits)
      }
      return strings.compactMap { digits in
        CardAccessNumber(digits: digits).map { number in
          CardCanOffer.Candidate(digits: digits, number: number)
        }
      }
    #else
      guard let number = cardAccessNumber() else { return [] }
      return [CardCanOffer.Candidate(digits: "", number: number)]
    #endif
  }

  /// Whether any stored number exists to try before asking.
  ///
  /// The entry must only appear when this is false or the stored
  /// numbers just failed: showing it while a mint is in flight invites
  /// typing that disturbs the attempt.
  public static func hasStoredNumbers() -> Bool {
    !cardAccessNumberCandidates().isEmpty
  }

  /// Remembers working digits for the card with this chip serial.
  ///
  /// Called by the driver after a number mints: the serial is known
  /// only once PACE has run, so the library grows one card at a time.
  public static func rememberCan(digits: String, chipSerial: ChipSerial) {
    guard let printed = PrintedSerial(chipSerial: chipSerial) else { return }
    CardCanOffer.remember(digits: digits, printedSerial: printed.value)
  }
}
