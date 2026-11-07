// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Keeps a credential action from starting while the phone is locked (RAPP
/// v26.11.2 §8.2 item 3).
///
/// An action passes before it takes a held PIN 1 or shows a PIN prompt. While
/// the phone is locked it waits here until the holder unlocks or the
/// operation ends. The gate is asked only before a credential use starts, so
/// a lock that comes after it stops nothing: a card command already sent and
/// a batch already approved run to their answer. Reads never come here.
@MainActor
internal final class CustodianUnlockGate<Ticket: Hashable & Sendable> {
  /// How many tickets that ended outside a wait are remembered, newest last.
  private let endedMemory = 8
  private let lockState: any CustodianLockState
  /// The suspended waits, by their operation.
  private var waiters: [Ticket: CheckedContinuation<Bool, Never>] = [:]
  /// Operations that ended outside a wait, so a late pass does not wait for
  /// an operation already over.
  private var ended: [Ticket] = []

  internal init(lockState: any CustodianLockState) {
    self.lockState = lockState
  }

  /// Waits until the phone is unlocked: true when the action may start,
  /// false when its operation ended first.
  ///
  /// An unlocked phone passes at once and tells no one. On a locked phone
  /// `tell` runs once, before the wait, and `withdraw` once after it,
  /// however it ended.
  internal func pass(
    _ ticket: Ticket,
    tell: @Sendable () async -> Void,
    withdraw: @Sendable () async -> Void
  ) async -> Bool {
    if forgetEnded(ticket) { return false }
    guard lockState.isLocked else { return true }
    await tell()
    let unlocked = await wait(ticket)
    await withdraw()
    return unlocked
  }

  /// Reads the lock again and lets every wait go if the phone is unlocked.
  internal func reassess() {
    guard !lockState.isLocked else { return }
    let released = waiters.values
    waiters.removeAll()
    for waiter in released {
      waiter.resume(returning: true)
    }
  }

  /// The operation of `ticket` ended: its wait ends, and a pass still to come
  /// does not wait.
  internal func end(_ ticket: Ticket) {
    if let waiter = waiters.removeValue(forKey: ticket) {
      waiter.resume(returning: false)
      return
    }
    ended.append(ticket)
    if ended.count > endedMemory { ended.removeFirst() }
  }

  /// Telling the holder can suspend, so the lock and the operation are read
  /// again here, with no suspension before the wait is registered.
  private func wait(_ ticket: Ticket) async -> Bool {
    if forgetEnded(ticket) { return false }
    guard lockState.isLocked else { return true }
    return await withCheckedContinuation { waiters[ticket] = $0 }
  }

  private func forgetEnded(_ ticket: Ticket) -> Bool {
    guard let index = ended.firstIndex(of: ticket) else { return false }
    ended.remove(at: index)
    return true
  }
}
