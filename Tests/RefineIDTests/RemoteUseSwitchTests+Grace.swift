// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import Testing

  @testable import RefineIDTestHost

  /// A lost session leaves the phone's identity standing for the row while
  /// it is still offered under the grace (RAPP v26.11.8 §8.4 item 3).
  extension RemoteUseSwitchTests {
    /// Who the borrowed certificate names in this test.
    private static let graceHolder = "TEST HOLDER"

    @Test("A dropped Bluetooth session keeps the offered identity on the row")
    internal func droppedBluetoothSessionKeepsTheIdentity() {
      let registry = PersistentTokenRegistry.shared
      let saved = (registry.holderLine, registry.holderOverBluetooth, registry.holderIsAdvertising)
      defer {
        registry.holderLine = saved.0
        registry.holderOverBluetooth = saved.1
        registry.holderIsAdvertising = saved.2
      }
      registry.holderIsAdvertising = false
      registry.holderOverBluetooth = true
      registry.holderLine = Self.graceHolder
      #expect(registry.holderIdentityStands)

      // The session over Bluetooth ends; the identity is still offered.
      registry.holderOverBluetooth = false
      #expect(!registry.holderInSight)
      #expect(registry.holderIdentityStands)

      // The grace lapsed or a withdrawal ended the offer.
      registry.holderLine = nil
      #expect(!registry.holderIdentityStands)
    }
  }
#endif
