// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RefineID

/// What the phone's Remote Access screen says for each combination.
@Suite
internal struct HolderServingStateTests {
  internal struct Case: Sendable, CustomTestStringConvertible {
    internal let name: String
    internal let enabled: Bool
    internal let paired: Bool
    internal let halted: Bool
    internal let connected: Bool
    internal let state: HolderServingState

    internal var testDescription: String { name }
  }

  internal static let cases: [Case] = [
    Case(name: "off", enabled: false, paired: true, halted: true, connected: true, state: .off),
    Case(
      name: "on, nothing paired", enabled: true, paired: false, halted: false, connected: false,
      state: .unpaired),
    Case(
      name: "waiting for a computer", enabled: true, paired: true, halted: false,
      connected: false, state: .listening),
    Case(
      name: "a computer is connected", enabled: true, paired: true, halted: false,
      connected: true, state: .connected),
    Case(
      name: "stopped, waiting for the holder", enabled: true, paired: true, halted: true,
      connected: false, state: .halted),
    Case(
      name: "a live session outranks a stop", enabled: true, paired: true, halted: true,
      connected: true, state: .connected),
    Case(
      name: "off with nothing else", enabled: false, paired: false, halted: false,
      connected: false, state: .off),
    Case(
      name: "nothing paired outranks a stop", enabled: true, paired: false, halted: true,
      connected: false, state: .unpaired),
  ]

  /// Each combination says its state.
  @Test(arguments: cases)
  internal func derivesTheState(_ testCase: Case) {
    let state = HolderServingState.derive(
      enabled: testCase.enabled,
      paired: testCase.paired,
      halted: testCase.halted,
      connected: testCase.connected
    )
    #expect(state == testCase.state)
  }
}
