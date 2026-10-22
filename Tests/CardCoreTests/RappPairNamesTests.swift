// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  @testable import CardCore
  import Foundation
  import Testing

  /// A pair's name is what its peer said after trimming; a blank is none.
  @Suite("RappPairNamesTests", .serialized)
  internal struct RappPairNamesTests {
    private static let pairID = Data(repeating: 0x5A, count: 16)

    @Test
    internal func paddedNameIsKeptTrimmed() {
      defer { RappPairNames.forget(pairID: Self.pairID) }
      RappPairNames.remember("  Alpha iPhone \n", pairID: Self.pairID)
      #expect(RappPairNames.name(forPairID: Self.pairID) == "Alpha iPhone")
    }

    @Test
    internal func blankNameLeavesThePairNameless() {
      defer { RappPairNames.forget(pairID: Self.pairID) }
      RappPairNames.remember("Alpha iPhone", pairID: Self.pairID)
      RappPairNames.remember("   ", pairID: Self.pairID)
      #expect(RappPairNames.name(forPairID: Self.pairID) == nil)
    }

    @Test
    internal func storedBlankReadsAsNoName() {
      defer { RappPairNames.forget(pairID: Self.pairID) }
      UserDefaults(suiteName: RappPairNames.testSuiteName)?.set(
        [Self.pairID.base64EncodedString(): " "], forKey: RappPairNames.key)
      #expect(RappPairNames.name(forPairID: Self.pairID) == nil)
    }

    /// A test host shares the app's bundle identifier, so names a test
    /// keeps must stay out of the app's own defaults, where the app keeps
    /// the names of real pairings.
    @Test
    internal func testNamesStayOutOfTheAppsDefaults() {
      defer { RappPairNames.forget(pairID: Self.pairID) }
      RappPairNames.remember("Alpha iPhone", pairID: Self.pairID)
      let appNames = UserDefaults.standard.dictionary(forKey: RappPairNames.key)
      #expect(appNames?[Self.pairID.base64EncodedString()] == nil)
    }
  }
#endif
