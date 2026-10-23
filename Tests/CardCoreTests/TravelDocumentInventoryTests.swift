// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// Reading the travel document's inventory, over a scripted card.
///
/// EF.COM opens with an LDS version and a Unicode version, both under
/// two-byte tags, and only then lists the data groups. A reader that
/// takes one byte as a tag reads the second byte of the first tag as
/// a length, walks off by one, never reaches the list, and reports a
/// card carrying five data groups as carrying none - which is exactly
/// what this app did until the walk understood two-byte tags.
@Suite
internal struct TravelDocumentInventoryTests {
  /// EF.COM exactly as a card answered it on 2026-08-04.
  private static let commonDataFile =
    "60175F0104303130385F36063034303030305C05617563676E"

  /// The same file with the signature's marker gone from the list.
  private static let withoutSignature =
    "60165F0104303130385F36063034303030305C0461756361"

  /// SELECT EF.COM, then the one read that carries its whole object:
  /// the file is far shorter than a chunk, so the reader asks once and
  /// the short answer ends it.
  private static func inventoryScript(file: String) -> [(String, String)] {
    [
      ("00A4020C02011E", "9000"),
      ("00B0000080", file + "9000"),
    ]
  }
  @Test
  internal func theInventorySurvivesTheTwoByteTagsBeforeTheList() throws {
    let channel = ScriptedChannel(
      Self.inventoryScript(file: Self.commonDataFile)
    )
    let operations = CardOperations(channel: channel)

    let inventory = try operations.readDataGroupInventory()

    #expect(inventory.count == 5)
    #expect(inventory.carriesDisplayedSignature)
    #expect(channel.isExhausted)
  }

  @Test
  internal func aCardListingNoSignatureIsBelieved() throws {
    let channel = ScriptedChannel(
      Self.inventoryScript(file: Self.withoutSignature)
    )
    let operations = CardOperations(channel: channel)

    let inventory = try operations.readDataGroupInventory()

    #expect(inventory.count == 4)
    #expect(!inventory.carriesDisplayedSignature)
  }

  @Test
  internal func absentDisplayedSignatureDoesNotReadDataGroupSeven() throws {
    let channel = ScriptedChannel(
      Self.inventoryScript(file: Self.withoutSignature)
    )
    let operations = CardOperations(channel: channel)

    #expect(try operations.readDisplayedSignature() == nil)
    #expect(channel.isExhausted)
  }

  @Test
  internal func listedButUnreadableDisplayedSignatureThrows() {
    let channel = ScriptedChannel(
      Self.inventoryScript(file: Self.commonDataFile)
        + [("00A4020C020107", "6A82")]
    )
    let operations = CardOperations(channel: channel)

    #expect(throws: CardOperationError.selectRejected(.fileNotFound)) {
      try operations.readDisplayedSignature()
    }
    #expect(channel.isExhausted)
  }

  @Test
  internal func oneInventoryGatesTheDisplayedSignature() throws {
    let signature = "670C0201015F4306FFD8FFE00010"
    let channel = ScriptedChannel(
      Self.inventoryScript(file: Self.commonDataFile)
        + [
          ("00A4020C020107", "9000"),
          ("00B0000080", signature + "9000"),
        ]
    )
    let operations = CardOperations(channel: channel)
    let inventory = try operations.readDataGroupInventory()

    #expect(
      try operations.readDisplayedSignature(listedBy: inventory)?.bytes
        == WireHex.data("FFD8FFE00010")
    )
    #expect(channel.isExhausted)
  }
}
