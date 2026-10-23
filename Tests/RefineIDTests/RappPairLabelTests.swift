// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

@testable import RefineID

/// The label a pairing is shown by: the peer's model when it extends the
/// peer's name or stands alone, otherwise the name.
@Suite(.serialized)
internal struct RappPairLabelTests {
  internal struct Case: Sendable, CustomTestStringConvertible {
    internal let name: String?
    internal let model: String?
    internal let label: String?

    internal var testDescription: String {
      "\(name ?? "no name") / \(model ?? "no model")"
    }
  }

  private static let phoneModel = "iPhone 15 Pro Max"

  private static let pairID = Data("pair label test".utf8)

  internal static let cases: [Case] = [
    Case(name: "iPhone", model: phoneModel, label: phoneModel),
    Case(name: "IPHONE", model: phoneModel, label: phoneModel),
    Case(name: phoneModel, model: phoneModel, label: phoneModel),
    Case(name: "Example Phone", model: "Android", label: "Example Phone"),
    Case(name: "Example Computer", model: "Mac", label: "Example Computer"),
    Case(name: "iPhone 15", model: "iPhone", label: "iPhone 15"),
    Case(name: nil, model: phoneModel, label: phoneModel),
    Case(name: "Example Phone", model: nil, label: "Example Phone"),
    Case(name: nil, model: nil, label: nil),
  ]

  @Test(arguments: cases)
  internal func labelFollowsNameAndModel(_ testCase: Case) {
    #expect(RappPairNames.label(name: testCase.name, model: testCase.model) == testCase.label)
  }

  /// A pairing whose peer sent its model beside a name the model extends
  /// is shown by the model.
  @Test
  internal func storedModelExtendingTheNameIsShown() {
    defer { RappPairNames.forget(pairID: Self.pairID) }
    RappPairNames.remember("iPhone", pairID: Self.pairID)
    RappPairNames.rememberModel(Self.phoneModel, pairID: Self.pairID)
    #expect(RappPairNames.displayName(forPairID: Self.pairID) == Self.phoneModel)
  }

  /// A pairing stored without a model keeps showing its name.
  @Test
  internal func pairingWithoutAModelIsShownByName() {
    defer { RappPairNames.forget(pairID: Self.pairID) }
    RappPairNames.remember("iPhone", pairID: Self.pairID)
    #expect(RappPairNames.displayName(forPairID: Self.pairID) == "iPhone")
  }

  @Test
  internal func pairingWithNeitherIsShownPlainly() {
    RappPairNames.forget(pairID: Self.pairID)
    #expect(
      RappPairNames.displayName(forPairID: Self.pairID) == String(localized: "Paired device"))
  }
}
