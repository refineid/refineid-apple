// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import CardCore

/// A computer names itself by its operating system and its host name; a
/// phone or a tablet by its own name alone.
@Suite
internal struct PeerDisplayNameTests {
  @Test("A computer's name is the system, a hyphen and the host name")
  internal func computerIsSystemThenHost() {
    #expect(
      PeerDisplayName.computer(system: PeerDisplayName.macSystem, host: "example-host").text
        == "macOS - example-host")
  }

  @Test("A phone or a tablet is named without its system")
  internal func handheldIsItsName() {
    #expect(PeerDisplayName.handheld(name: "iPhone 15 Pro Max").text == "iPhone 15 Pro Max")
    #expect(PeerDisplayName.handheld(name: "iPad Air 11-inch (M2)").text == "iPad Air 11-inch (M2)")
  }

  @Test("Blanks around the device's name are dropped")
  internal func nameIsTrimmed() {
    #expect(
      PeerDisplayName.computer(system: PeerDisplayName.macSystem, host: "  example-host\n").text
        == "macOS - example-host")
    #expect(PeerDisplayName.handheld(name: " example-phone\n").text == "example-phone")
  }
}
