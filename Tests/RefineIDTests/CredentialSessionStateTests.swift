// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

@testable import RefineIDTestHost

/// What one card session remembers about its credentials, and for how long.
@Suite
internal struct CredentialSessionStateTests {
  private static let refusedDigits = "000000"

  private static func refusedPin1() throws -> PinFingerprint {
    try #require(Pin1Entry(digits: refusedDigits)).sessionFingerprint()
  }

  private static func refusedPin2() throws -> PinFingerprint {
    try #require(Pin2Entry(digits: refusedDigits)).sessionFingerprint()
  }

  @Test("A session end forgets the probes and the refused PINs")
  internal func sessionEndForgetsEverything() throws {
    var state = CredentialSessionState()
    state.markProbed(.pin1)
    state.recordNegativePin(try Self.refusedPin2(), role: .pin2)
    #expect(state.probedRoles.contains(.pin1))
    #expect(state.isNegativePin(try Self.refusedPin2()))
    state.sessionEnded()
    #expect(state == CredentialSessionState())
    #expect(!state.isNegativePin(try Self.refusedPin2()))
  }

  @Test("A refused PIN is probed again before its next verification")
  internal func refusedPinIsProbedAgain() throws {
    var state = CredentialSessionState()
    state.markProbed(.pin1)
    state.recordNegativePin(try Self.refusedPin1(), role: .pin1)
    #expect(!state.probedRoles.contains(.pin1))
    #expect(state.isNegativePin(try Self.refusedPin1()))
  }

  @Test("Digits refused in one role are not refused in the other")
  internal func refusalIsBoundToTheRole() throws {
    var state = CredentialSessionState()
    state.recordNegativePin(try Self.refusedPin1(), role: .pin1)
    #expect(!state.isNegativePin(try Self.refusedPin2()))
  }

  @Test("A write through the box is visible to the next read at once")
  internal func boxWriteIsVisibleAtOnce() throws {
    let box = CredentialSessionBox()
    box.mutate { $0.markProbed(.pin1) }
    #expect(box.read().probedRoles.contains(.pin1))
    let refused = try Self.refusedPin1()
    box.mutate { $0.recordNegativePin(refused, role: .pin1) }
    #expect(box.read().isNegativePin(refused))
    box.mutate { $0.sessionEnded() }
    #expect(box.read() == CredentialSessionState())
  }
}
