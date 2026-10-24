// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RefineIDTestHost

@Suite
internal struct DeviceModelTests {
  @Test
  internal func aListedIdentifierIsNamedAsOnTheBox() {
    #expect(DeviceModel.name(ofMachine: "iPhone16,2") == "iPhone 15 Pro Max")
    #expect(DeviceModel.name(ofMachine: "iPhone14,6") == "iPhone SE (3rd generation)")
  }

  @Test
  internal func anUnlistedIdentifierIsShownAsItIs() {
    #expect(DeviceModel.name(ofMachine: "iPhone99,9") == "iPhone99,9")
  }

  @Test
  internal func theMachineIdentifierIsNeverEmpty() {
    #expect(!DeviceModel.machineIdentifier.isEmpty)
  }
}
