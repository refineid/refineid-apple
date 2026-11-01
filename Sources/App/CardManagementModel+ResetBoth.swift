// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore

extension CardManagementModel {
  /// Resets PIN 1 and then PIN 2 with one PUK entry.
  ///
  /// Each reset is its own card operation with its own PUK floor check.
  /// PIN 2 is sent only after PIN 1 was reset, and the counters are
  /// applied once both have answered, so the form stays on screen while
  /// the card works.
  internal func unblockBoth(puk: String, newPin1: String, newPin2: String) async -> Bool {
    guard beginCardOperation() else { return false }
    working = true
    failure = nil
    notice = nil
    let first = await CardMaintenance.unblockPin1(
      puk: puk,
      new: newPin1,
      transport: transport,
      cardAccessNumber: offeredCardAccessNumber
    )
    guard first.outcome == .success else {
      working = false
      failure = message(for: first.outcome, presenting: .puk, spending: .puk)
      if let snapshot = first.snapshot {
        apply(snapshot, preservingOutcome: true)
      }
      return false
    }
    let second = await CardMaintenance.unblockPin2(
      puk: puk,
      new: newPin2,
      transport: transport,
      cardAccessNumber: offeredCardAccessNumber
    )
    working = false
    if second.outcome == .success {
      notice = String(localized: "PIN 1 and PIN 2 reset.")
    } else {
      failure = message(for: second.outcome, presenting: .puk, spending: .puk)
        .map { String(localized: "PIN 1 was reset, but PIN 2 was not: \($0)") }
    }
    if let snapshot = second.snapshot ?? first.snapshot {
      apply(snapshot, preservingOutcome: true)
    }
    return second.outcome == .success
  }
}
