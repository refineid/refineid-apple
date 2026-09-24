// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation
  import Testing

  @testable import RefineID

  /// Verifies timeout configurations for desktop smart card readers.
  @Suite
  internal struct SmartCardTimeoutTests {
    @Test
    internal func readerResponseBudgetAccommodatesSlowCards() {
      // The reader budget must provide at least 60 seconds to accommodate
      // Thales CAN-PACE progressive delays (which can reach 45+ seconds)
      // and heavy cryptographic operations over PC/SC without timing out prematurely.
      #expect(SmartCardChannel.readerResponseSeconds >= 60)
      #expect(SmartCardChannel.nearFieldResponseSeconds == 10)
    }

    @Test
    internal func slotNameResolvesToExpectedWaitPolicy() {
      #expect(
        SmartCardChannel.defaultWait(
          forSlotNamed: "ACS ACR1581 1S Dual Reader(1)") == .reader)
      #expect(
        SmartCardChannel.defaultWait(
          forSlotNamed: "Built-in NFC Slot") == .nearField)
      #expect(
        SmartCardChannel.defaultWait(
          forSlotNamed: "Identiv uTrust 3700 F") == .reader)
    }
  }

#endif
