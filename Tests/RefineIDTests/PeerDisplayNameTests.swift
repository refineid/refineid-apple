// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RefineIDTestHost

/// A device names itself by its operating system and its own name.
@Suite
internal struct PeerDisplayNameTests {
  @Test("The name is the system, a hyphen and the device's name")
  internal func systemThenHost() {
    #expect(
      PeerDisplayName(system: PeerDisplayName.macSystem, host: "example-host").text
        == "macOS - example-host")
    #expect(
      PeerDisplayName(system: PeerDisplayName.iPhoneSystem, host: "example-phone").text
        == "iOS - example-phone")
    #expect(
      PeerDisplayName(system: PeerDisplayName.iPadSystem, host: "example-tablet").text
        == "iPadOS - example-tablet")
  }

  @Test("Blanks around the device's name are dropped")
  internal func hostIsTrimmed() {
    #expect(
      PeerDisplayName(system: PeerDisplayName.macSystem, host: "  example-host\n").text
        == "macOS - example-host")
  }
}
