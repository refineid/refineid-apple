// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  @testable import CardCore
  import Testing

  /// A Mac names itself by its host name, or by the fallback host when it
  /// has none (RAPP v26.11.8 §4.3 item 3).
  @Suite
  internal struct RappLocalNameTests {
    @Test("Two empty host-name sources fall back to Mac")
    internal func emptySourcesFallBack() {
      #expect(
        RappLocalName.computerDeviceName(localHostName: nil, localizedName: nil) == "macOS - Mac")
      #expect(
        RappLocalName.computerDeviceName(localHostName: "", localizedName: "") == "macOS - Mac")
      #expect(
        RappLocalName.computerDeviceName(localHostName: "  \n", localizedName: " \n")
          == "macOS - Mac")
    }

    @Test("The first source that names one wins")
    internal func firstNamingSourceWins() {
      #expect(
        RappLocalName.computerDeviceName(localHostName: "example-host", localizedName: nil)
          == "macOS - example-host")
      #expect(
        RappLocalName.computerDeviceName(localHostName: nil, localizedName: "example-host")
          == "macOS - example-host")
      #expect(
        RappLocalName.computerDeviceName(localHostName: "", localizedName: "example-host")
          == "macOS - example-host")
      #expect(
        RappLocalName.computerDeviceName(
          localHostName: "first-host", localizedName: "second-host") == "macOS - first-host")
    }

    @Test("Blanks around the host name are dropped")
    internal func hostNameIsTrimmed() {
      #expect(
        RappLocalName.computerDeviceName(localHostName: "  example-host\n", localizedName: nil)
          == "macOS - example-host")
    }
  }
#endif
