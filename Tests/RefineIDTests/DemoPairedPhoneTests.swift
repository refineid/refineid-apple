// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import Testing

  @testable import RefineID

  /// The demonstration's paired phone draws the line a paired phone draws.
  @Suite
  internal struct DemoPairedPhoneTests {
    @Test
    @MainActor
    internal func aReadyCardNamesTheHolder() {
      #expect(
        IdentityLine.derive(DemoPairedPhone.facts(availability: .ready))
          == .paired(.holder))
    }

    @Test
    @MainActor
    internal func noCardIsStillConnecting() {
      #expect(
        IdentityLine.derive(DemoPairedPhone.facts(availability: .noCard))
          == .paired(.connecting))
    }
  }

#endif
