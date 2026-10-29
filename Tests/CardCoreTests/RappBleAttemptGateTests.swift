// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// One CPace attempt at a time across a BLE custodian's links (RAPP
/// v26.10.29 §3.3 item 6, §4.2 "Busy Refusal" item 2).
@Suite
internal struct RappBleAttemptGateTests {
  @Test("A holder that disconnects frees the gate for another central's step 1")
  internal func aDisconnectedHolderFreesTheGate() {
    var gate = RappBleAttemptGate()
    let holder = UUID()
    let other = UUID()
    #expect(gate.admit(holder) { true })
    #expect(!gate.admit(other) { true }, "one attempt at a time")
    gate.release(other)
    #expect(!gate.admit(other) { true }, "only the holder's link frees it")
    gate.release(holder)
    #expect(gate.admit(other) { true })
  }

  @Test("Every link gone frees the gate, and the custodian still decides")
  internal func everyLinkGoneFreesTheGate() {
    var gate = RappBleAttemptGate()
    let holder = UUID()
    let other = UUID()
    #expect(gate.admit(holder) { true })
    gate.releaseAll()
    #expect(!gate.admit(other) { false }, "a custodian that cannot admit refuses")
    #expect(gate.admit(other) { true })
  }
}
