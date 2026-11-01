// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// This file is a byte table: every literal below is one byte of a
// card's answer to reset, quoted from the document named below. Naming
// each byte individually would hide the pattern the table exists to
// show -- which bytes the cards share and which ones tell them apart.
/// The cards DVV issues, by their historical bytes.
///
/// Provenance: *Technology note - ATR/ATS bytes* v1.0, DVV ICT Unit,
/// 12.8.2024, read on 2026-07-27; the historical bytes below are what
/// this module's parser extracts from the answers to reset printed
/// there. `Documentation/card-types.md` keeps the full table with its
/// dates and the contactless forms.
///
/// The note is a document with a date on it, not a description of every
/// card in circulation: the card measured here on 2026-07-27 is a
/// MultiApp v5 whose version bytes are not the ones it lists. So the
/// families below exist as well, and an unrecognized variant is named
/// as a family rather than rounded to the nearest exact row.
internal enum FineidCardTypeValues {
  /// One card, by the exact historical bytes it answers with.
  internal struct Exact {
    /// The bytes this card answers with.
    internal let historicalBytes: [UInt8]

    /// What DVV calls it.
    internal let name: String
  }

  /// A platform generation, by the bytes its members begin with.
  internal struct Family {
    /// The prefix its members share.
    internal let historicalPrefix: [UInt8]

    /// What the generation is called.
    internal let name: String
  }

  /// Every card the note names, most recent first.
  ///
  /// Citizen and organizational cards alike read through the same
  /// operations: where the S4-2 organization layout differs from S4-1,
  /// the certificate slots list both homes and the card's SELECT answer
  /// decides. This table only names what is in the reader.
  internal static let exact: [Exact] = [
    Exact(
      historicalBytes: [
        0x80, 0x31, 0xB8, 0x65, 0xB0, 0x85, 0x05, 0x00, 0x11, 0x12, 0x24, 0x60,
        0x82, 0x90, 0x00,
      ],
      name: "Thales MultiApp v5.0 (FINEID S4-1 v4.0)"),
    Exact(
      historicalBytes: [
        0x80, 0x31, 0xB8, 0x65, 0xB0, 0x85, 0x04, 0x02, 0x1B, 0x12, 0x00, 0xF6,
        0x82, 0x90, 0x00,
      ],
      name: "Gemalto MultiApp v4.2 (FINEID S4-1 v3.1)"),
    Exact(
      historicalBytes: [
        0x80, 0x31, 0xB8, 0x65, 0xB0, 0x85, 0x03, 0x00, 0xEF, 0x12, 0x00, 0xF6,
        0x82, 0x90, 0x00,
      ],
      name: "Gemalto MultiApp v3.0 (FINEID S4-1 v3.0)"),
    Exact(
      historicalBytes: [
        0x00, 0x31, 0xB8, 0x64, 0x04, 0x29, 0xEC, 0xC1, 0x73, 0x94, 0x01, 0x80,
        0x83,
      ],
      name: "Idemia Cosmo X (FINEID S1 v5.0)"),
    Exact(
      historicalBytes: [
        0x00, 0x31, 0xB8, 0x64, 0x04, 0x29, 0xEC, 0xC1, 0x73, 0x94, 0x01, 0x80,
        0x82,
      ],
      name: "Idemia ID.me IDeal Citiz 2.17-i (FINEID S1 v4.0)"),
    Exact(
      historicalBytes: [
        0x00, 0x31, 0xB8, 0x64, 0x04, 0x29, 0xEC, 0xC1, 0x73, 0x94, 0x01, 0x80,
        0x82, 0x90, 0x00,
      ],
      name: "Oberthur Cosmo v7 IAS-ECC"),
    Exact(
      historicalBytes: [
        0x80, 0x62, 0x00, 0x51, 0x56, 0x46, 0x69, 0x6E, 0x45, 0x49, 0x44,
      ],
      name: "Setec SetCOS 5.1.X"),
    Exact(
      historicalBytes: [
        0x80, 0x62, 0x01, 0x54, 0x56, 0x46, 0x69, 0x6E, 0x45, 0x49, 0x44,
      ],
      name: "Segenmark FINEID"),
  ]

  /// The generations, for a card whose exact bytes are not listed.
  ///
  /// The shared prefix is the card capabilities and the generation byte
  /// after them; what differs within a generation is the version and
  /// mask that follow. Ordered longest first is unnecessary here because
  /// all three are the same length, but the lookup takes the first match
  /// and these are mutually exclusive.
  internal static let families: [Family] = [
    Family(
      historicalPrefix: multiAppCapabilities + [fifthGeneration],
      name: "Thales MultiApp v5"),
    Family(
      historicalPrefix: multiAppCapabilities + [fourthGeneration],
      name: "Gemalto MultiApp v4"),
    Family(
      historicalPrefix: multiAppCapabilities + [thirdGeneration],
      name: "Gemalto MultiApp v3"),
  ]

  /// The card-capability bytes every MultiApp answer opens with, shared
  /// by all three generations DVV has issued.
  private static let multiAppCapabilities: [UInt8] = [
    0x80, 0x31, 0xB8, 0x65, 0xB0, 0x85,
  ]

  /// The generation byte that follows them, which is what separates the
  /// three; the version and mask bytes after it separate variants within
  /// a generation.
  private static let thirdGeneration: UInt8 = 0x03

  /// Gemalto MultiApp v4's generation byte.
  private static let fourthGeneration: UInt8 = 0x04

  /// Thales MultiApp v5's generation byte.
  private static let fifthGeneration: UInt8 = 0x05
}
