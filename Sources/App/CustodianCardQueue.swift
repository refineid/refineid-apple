// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Hands the card to one operation at a time, across every session the
/// custodian holds (RAPP v26.10.29 §8.2 item 2, STPA CC-59).
///
/// Operations take the card in the order they joined. One that joins while
/// another holds the card waits; the holder leaves once its operation is
/// over and its card exchange done, and the card goes to the operation
/// that waited longest. A waiting operation that ends first leaves without
/// ever holding the card. Nothing else touches the card for an operation
/// that does not hold it, so the card commands of two operations never
/// interleave.
@MainActor
internal final class CustodianCardQueue<Ticket: Hashable & Sendable> {
  /// The operation holding the card; nil while the card is free.
  internal private(set) var holder: Ticket?

  /// The operations waiting for the card, oldest first.
  internal private(set) var waiting: [Ticket] = []

  /// The suspended waits of operations still in ``waiting``.
  private var takers: [Ticket: CheckedContinuation<Bool, Never>] = [:]

  /// Joins the queue: true when `ticket` holds the card at once, false when
  /// it waits behind another operation.
  internal func join(_ ticket: Ticket) -> Bool {
    if holder == ticket { return true }
    if waiting.contains(ticket) { return false }
    guard holder == nil else {
      waiting.append(ticket)
      return false
    }
    holder = ticket
    return true
  }

  /// Joins the queue and waits for the card: true once `ticket` holds it,
  /// false when it left first.
  ///
  /// `queued` runs once, before the wait, when another operation holds the
  /// card, so the waiting operation's requester hears it is queued, and
  /// nothing when it is not.
  internal func take(_ ticket: Ticket, queued: () async -> Void) async -> Bool {
    if !join(ticket) { await queued() }
    return await turn(of: ticket)
  }

  /// Waits until `ticket` holds the card: true once it does, false when it
  /// left the queue first or never joined.
  internal func turn(of ticket: Ticket) async -> Bool {
    if holder == ticket { return true }
    guard waiting.contains(ticket) else { return false }
    return await withCheckedContinuation { continuation in
      takers[ticket] = continuation
    }
  }

  /// Takes `ticket` out: a holder releases the card to the operation that
  /// waited longest, a waiting one leaves the queue.
  internal func leave(_ ticket: Ticket) {
    if holder == ticket {
      holder = nil
      grantNext()
      return
    }
    guard let index = waiting.firstIndex(of: ticket) else { return }
    waiting.remove(at: index)
    takers.removeValue(forKey: ticket)?.resume(returning: false)
  }

  private func grantNext() {
    guard holder == nil, !waiting.isEmpty else { return }
    let next = waiting.removeFirst()
    holder = next
    takers.removeValue(forKey: next)?.resume(returning: true)
  }
}
