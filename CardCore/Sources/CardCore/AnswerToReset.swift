// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The historical bytes of an answer to reset, parsed as ISO 7816-3
/// defines them.
///
/// The historical bytes are the part that identifies a card across every
/// way of reaching it. One card answers differently on each interface
/// and through each reader -- a contact answer to reset frames them one
/// way, a card's own ATS another, and a PC/SC reader synthesizes a third
/// -- while the historical bytes inside are the same.
///
/// They have to be parsed rather than found. The obvious shortcut is to
/// search for the `80` category byte and take everything after it, and
/// it is wrong: two of the cards DVV issues carry an `80` among their
/// interface bytes, so the search finds that one and returns a string
/// that begins in the middle of the header. That mistake was made once
/// while this was being written, which is why the structure is walked
/// properly here.
///
/// The walk: `TS` names the convention, `T0` carries how many historical
/// bytes there are in its low nibble and which interface bytes follow in
/// its high nibble, and each `TD` byte says the same about the group
/// after it. Skip those groups and the historical bytes are what remain,
/// however many `T0` promised.
public struct AnswerToReset: Equatable, Sendable {
  /// Hex of the historical bytes: the card model's name in every
  /// framing.
  ///
  /// The same card answers differently on each interface and through
  /// each reader, and the historical bytes are the part that identifies
  /// it in all of them (`Documentation/card-types.md`). One card MODEL,
  /// not one card: a production batch shares the answer, so this keys
  /// which stored numbers are worth trying, never which card is present.
  public var modelKey: String {
    historicalBytes.map { String(format: "%02x", $0) }.joined()
  }

  /// The historical bytes, in order.
  public let historicalBytes: [UInt8]

  /// Parses `bytes`, or answers nil when they are not an answer to reset
  /// this can make sense of.
  ///
  /// Nil is returned rather than an empty reading, because "this card
  /// says nothing about itself" and "this is not something we can read"
  /// deserve different words on a screen.
  public init?(bytes: Data) {
    let raw = Array(bytes)
    guard raw.count > AnswerToResetValues.formatByteIndex else { return nil }
    let format = raw[AnswerToResetValues.formatByteIndex]
    let count = Int(format & AnswerToResetValues.historicalCountMask)
    var next = format >> AnswerToResetValues.interfacePresenceShift
    var index = AnswerToResetValues.formatByteIndex + 1

    // Each group announces the next one. TA, TB and TC carry no
    // structure worth reading here and are stepped over; only TD says
    // whether another group follows.
    while next & AnswerToResetValues.protocolByteBit != 0 {
      for bit in AnswerToResetValues.interfaceByteBits where next & bit != 0 {
        index += 1
      }
      guard index < raw.count else { return nil }
      let protocolByte = raw[index]
      index += 1
      next = protocolByte >> AnswerToResetValues.interfacePresenceShift
    }
    for bit in AnswerToResetValues.interfaceByteBits where next & bit != 0 {
      index += 1
    }

    guard index + count <= raw.count else { return nil }
    self.historicalBytes = Array(raw[index..<(index + count)])
  }

  /// Whether `bytes` is the answer a PC/SC reader synthesizes for a
  /// card on its contactless interface.
  ///
  /// A contactless card has no answer to reset of its own; the reader
  /// constructs one with a fixed prefix (PC/SC part 3), and that
  /// prefix says which interface the card is on without opening a
  /// session or sending the card anything. A reader's slot answer is
  /// enough to ask this of.
  public static func indicatesContactlessInterface(bytes: Data) -> Bool {
    let prefix = AnswerToResetValues.synthesizedContactlessPrefix
    let masks = AnswerToResetValues.synthesizedContactlessMasks
    guard bytes.count > prefix.count else { return false }
    return zip(Array(bytes.prefix(prefix.count)), zip(prefix, masks))
      .allSatisfy { byte, expectation in
        byte & expectation.1 == expectation.0
      }
  }

  /// Whether `bytes` carries an EstEID 2018 (Cosmo v8 or Cosmo X)
  /// historical-bytes marker (ID1 Developer Guide 2025 sections 5.2-5.3).
  ///
  /// Routing hint only for selecting the IAS-ECC root AID before PACE on
  /// NFC; never a trust or identity assertion.
  public static func indicatesEstonian2018(bytes: Data) -> Bool {
    bytes.contains(EstonianEidValues.legacyCosmoV8Marker)
      || bytes.contains(EstonianEidValues.legacyCosmoXMarker)
  }
}
