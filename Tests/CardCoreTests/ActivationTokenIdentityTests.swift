// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import CardCore

/// The activation token names its reader slot, and the slot reads back.
internal struct ActivationTokenIdentityTests {
  private static let slotName = "Example Reader 01 00"
  private static let tokenClass = "fi.refineid.token"

  @Test
  internal func slotNameReadsBackFromTheTokenIdentifier() {
    let instance = ActivationTokenIdentity.instanceID(forSlotNamed: Self.slotName)
    let tokenID = Self.tokenClass + ":" + instance
    #expect(ActivationTokenIdentity.recognizes(tokenID: tokenID))
    #expect(ActivationTokenIdentity.slotName(tokenID: tokenID) == Self.slotName)
  }

  @Test
  internal func anIdentityTokenNamesNoSlot() {
    #expect(ActivationTokenIdentity.slotName(tokenID: Self.tokenClass + ":identity") == nil)
  }
}
