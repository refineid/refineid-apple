// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineIDTestHost

/// The card serves one whole operation at a time across every session,
/// first come first served, and a waiting operation that ends leaves the
/// queue (RAPP v26.10.29 §8.2 item 2, STPA CC-59).
@MainActor
@Suite
internal struct CustodianCardQueueTests {
  /// What the operations did, in order.
  @MainActor
  private final class Log {
    var lines: [String] = []
  }

  /// Operations of different sessions, by the computer that asked.
  private static let mac = "mac operation"
  private static let laptop = "laptop operation"
  private static let workstation = "workstation operation"

  /// Yields enough for a resumed waiter to record what it saw.
  private static let yields = 20

  /// Lets every task the test started run as far as it can.
  private static func settle() async {
    for _ in 0..<Self.yields {
      await Task.yield()
    }
  }

  @Test("The first operation holds the card at once; the next waits")
  internal func firstHoldsNextWaits() {
    let queue = CustodianCardQueue<String>()
    #expect(queue.join(Self.mac))
    #expect(!queue.join(Self.laptop))
    #expect(queue.holder == Self.mac)
    #expect(queue.waiting == [Self.laptop])
  }

  @Test("Only an operation that waits behind another hears it is queued, once")
  internal func queuedOnlyWhenWaiting() async {
    let queue = CustodianCardQueue<String>()
    let heard = Log()
    #expect(await queue.take(Self.mac) { heard.lines.append(Self.mac) })
    #expect(heard.lines.isEmpty)
    let laptopTurn = Task {
      await queue.take(Self.laptop) { heard.lines.append(Self.laptop) }
    }
    await Self.settle()
    #expect(heard.lines == [Self.laptop])
    queue.leave(Self.mac)
    #expect(await laptopTurn.value)
    #expect(heard.lines == [Self.laptop])
  }

  @Test("The card goes to the operations in the order they joined")
  internal func firstComeFirstServed() async {
    let queue = CustodianCardQueue<String>()
    let served = Log()
    _ = queue.join(Self.mac)
    for operation in [Self.laptop, Self.workstation] {
      _ = queue.join(operation)
      Task {
        if await queue.turn(of: operation) { served.lines.append(operation) }
      }
    }
    await Self.settle()
    #expect(served.lines.isEmpty)
    queue.leave(Self.mac)
    await Self.settle()
    #expect(served.lines == [Self.laptop])
    queue.leave(Self.laptop)
    await Self.settle()
    #expect(served.lines == [Self.laptop, Self.workstation])
  }

  @Test("A waiting operation never touches the card while another holds it")
  internal func noInterleaving() async {
    let queue = CustodianCardQueue<String>()
    let commands = Log()
    _ = queue.join(Self.mac)
    _ = queue.join(Self.laptop)
    let waiter = Task {
      guard await queue.turn(of: Self.laptop) else { return }
      commands.lines.append("laptop select")
      commands.lines.append("laptop sign")
    }
    commands.lines.append("mac select")
    await Self.settle()
    commands.lines.append("mac sign")
    queue.leave(Self.mac)
    await waiter.value
    #expect(commands.lines == ["mac select", "mac sign", "laptop select", "laptop sign"])
  }

  @Test("A waiting operation that ends leaves the queue without the card")
  internal func endedOperationLeavesTheQueue() async {
    let queue = CustodianCardQueue<String>()
    _ = queue.join(Self.mac)
    _ = queue.join(Self.laptop)
    _ = queue.join(Self.workstation)
    let laptopTurn = Task { await queue.turn(of: Self.laptop) }
    await Self.settle()
    queue.leave(Self.laptop)
    #expect(await laptopTurn.value == false)
    #expect(queue.waiting == [Self.workstation])
    queue.leave(Self.mac)
    #expect(queue.holder == Self.workstation)
    #expect(await queue.turn(of: Self.workstation))
  }

  @Test("An operation granted the card before it waited holds it at once")
  internal func grantBeforeWaitIsKept() async {
    let queue = CustodianCardQueue<String>()
    _ = queue.join(Self.mac)
    _ = queue.join(Self.laptop)
    queue.leave(Self.mac)
    #expect(await queue.turn(of: Self.laptop))
  }

  @Test("An operation that never joined, or already left, has no turn")
  internal func strangerHasNoTurn() async {
    let queue = CustodianCardQueue<String>()
    #expect(await queue.turn(of: Self.mac) == false)
    _ = queue.join(Self.mac)
    queue.leave(Self.mac)
    #expect(queue.holder == nil)
    #expect(await queue.turn(of: Self.mac) == false)
  }
}
