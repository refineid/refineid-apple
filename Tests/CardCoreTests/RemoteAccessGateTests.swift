// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// Remote card use stays off until the holder opts in.
@Suite(.serialized)
internal struct RemoteAccessGateTests {
  private static let suiteName = "fi.refineid.tests.remote-access-gate"

  private static func isolatedStore() throws -> UserDefaults {
    let store = try #require(UserDefaults(suiteName: suiteName))
    store.removePersistentDomain(forName: suiteName)
    return store
  }

  @Test("Remote access starts off")
  internal func defaultsOff() {
    RemoteAccessGate.clearSessionOverride()
    #expect(RemoteAccessGate.effectiveEnabled() == false)
  }

  @Test("The session choice wins over the stored default")
  internal func sessionOverrideWins() {
    RemoteAccessGate.setSessionOverride(true)
    #expect(RemoteAccessGate.effectiveEnabled() == true)
    RemoteAccessGate.setSessionOverride(false)
    #expect(RemoteAccessGate.effectiveEnabled() == false)
    RemoteAccessGate.clearSessionOverride()
    #expect(RemoteAccessGate.effectiveEnabled() == false)
  }

  @Test("Enabling in tests stays in memory")
  internal func testChoiceStaysInMemory() {
    let standard = UserDefaults.standard
    let before = standard.bool(forKey: RemoteAccessGate.enabledDefaultsKey)
    RemoteAccessGate.setEnabled(true)
    #expect(RemoteAccessGate.effectiveEnabled() == true)
    #expect(standard.bool(forKey: RemoteAccessGate.enabledDefaultsKey) == before)
    RemoteAccessGate.clearSessionOverride()
  }

  @Test("The stored choice round-trips with an off default")
  internal func storedRoundTrip() throws {
    let store = try Self.isolatedStore()
    #expect(RemoteAccessGate.storedEnabled(in: store) == false)
    RemoteAccessGate.setStoredEnabled(true, in: store)
    #expect(RemoteAccessGate.storedEnabled(in: store) == true)
    RemoteAccessGate.setStoredEnabled(false, in: store)
    #expect(RemoteAccessGate.storedEnabled(in: store) == false)
    store.removePersistentDomain(forName: Self.suiteName)
  }

  #if os(macOS)
    @Test("macOS keeps its established requester behavior")
    internal func macOSAlwaysOn() {
      #expect(RemoteAccessGate.isEnabled == true)
    }
  #endif
}
