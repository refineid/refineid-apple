// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  @testable import CardCore
  import Foundation
  import Testing

  /// A pair's name and model are what its peer said after trimming; a
  /// blank is none.
  @Suite("RappPairNamesTests", .serialized)
  internal struct RappPairNamesTests {
    private static let pairID = Data(repeating: 0x5A, count: 16)
    private static let name = "Example Phone"
    private static let model = "iPhone 15 Pro Max"

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

    @Test
    internal func paddedModelIsKeptTrimmed() {
      defer { RappPairNames.forget(pairID: Self.pairID) }
      RappPairNames.rememberModel("  \(Self.model) \n", pairID: Self.pairID)
      #expect(RappPairNames.model(forPairID: Self.pairID) == Self.model)
    }

    /// A blank model forgets the model and leaves the name.
    @Test
    internal func blankModelLeavesTheNameAlone() {
      defer { RappPairNames.forget(pairID: Self.pairID) }
      RappPairNames.remember(Self.name, pairID: Self.pairID)
      RappPairNames.rememberModel(Self.model, pairID: Self.pairID)
      RappPairNames.rememberModel(" ", pairID: Self.pairID)
      #expect(RappPairNames.model(forPairID: Self.pairID) == nil)
      #expect(RappPairNames.name(forPairID: Self.pairID) == Self.name)
    }

    /// Models live under their own key; the names map keeps its shape.
    @Test
    internal func modelsStayOutOfTheNamesMap() throws {
      defer { RappPairNames.forget(pairID: Self.pairID) }
      RappPairNames.remember(Self.name, pairID: Self.pairID)
      RappPairNames.rememberModel(Self.model, pairID: Self.pairID)
      let suite = try #require(UserDefaults(suiteName: RappPairNames.testSuiteName))
      let names = suite.dictionary(forKey: RappPairNames.key) as? [String: String]
      let models = suite.dictionary(forKey: RappPairNames.modelKey) as? [String: String]
      #expect(names?[Self.pairID.base64EncodedString()] == Self.name)
      #expect(models?[Self.pairID.base64EncodedString()] == Self.model)
      let appModels = UserDefaults.standard.dictionary(forKey: RappPairNames.modelKey)
      #expect(appModels?[Self.pairID.base64EncodedString()] == nil)
    }

    @Test
    internal func forgettingAPairDropsItsNameAndModel() {
      RappPairNames.remember(Self.name, pairID: Self.pairID)
      RappPairNames.rememberModel(Self.model, pairID: Self.pairID)
      RappPairNames.forget(pairID: Self.pairID)
      #expect(RappPairNames.name(forPairID: Self.pairID) == nil)
      #expect(RappPairNames.model(forPairID: Self.pairID) == nil)
    }

    @Test
    internal func forgettingAllDropsEveryNameAndModel() {
      RappPairNames.remember(Self.name, pairID: Self.pairID)
      RappPairNames.rememberModel(Self.model, pairID: Self.pairID)
      RappPairNames.forgetAll()
      #expect(RappPairNames.name(forPairID: Self.pairID) == nil)
      #expect(RappPairNames.model(forPairID: Self.pairID) == nil)
    }
  }
#endif
