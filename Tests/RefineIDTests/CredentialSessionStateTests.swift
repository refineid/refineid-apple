// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

@testable import RefineID

/// What one card session remembers about its credentials, and for how long.
@Suite
internal struct CredentialSessionStateTests {
  private static let refusedDigits = "000000"

  @Test("A session end forgets the probes and the refused digits")
  internal func sessionEndForgetsEverything() {
    var state = CredentialSessionState()
    state.markProbed(.pin1)
    state.recordNegativePin(Self.refusedDigits)
    #expect(state.probedRoles.contains(.pin1))
    #expect(state.isNegativePin(Self.refusedDigits))
    state.sessionEnded()
    #expect(state == CredentialSessionState())
    #expect(!state.isNegativePin(Self.refusedDigits))
  }

  @Test("A write through the box is visible to the next read at once")
  internal func boxWriteIsVisibleAtOnce() {
    let box = CredentialSessionBox()
    box.mutate { $0.markProbed(.pin1) }
    #expect(box.read().probedRoles.contains(.pin1))
    box.mutate { $0.recordNegativePin(Self.refusedDigits) }
    #expect(box.read().isNegativePin(Self.refusedDigits))
    box.mutate { $0.sessionEnded() }
    #expect(box.read() == CredentialSessionState())
  }
}
