// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The parts of a PDF's cross-reference chain an incremental update
/// needs (ISO 32000-1 §7.5).
///
/// Everything here counts bytes, never characters. A cross-reference
/// table addresses byte offsets, and a PDF is binary with ASCII
/// structure in it: decoding the file to a string first would be wrong
/// on any document with CRLF line endings, where `\r\n` is one Swift
/// Character but two bytes - every offset after the first line ending
/// would then be short by the number of line endings before it.
internal struct PdfDocumentIndex {
  /// Where one live object's bytes sit.
  internal enum ObjectLocation: Equatable, Hashable, Sendable {
    /// Inside an object stream: the stream's object number and this
    /// object's position among its contents (ISO 32000-1 §7.5.7).
    case compressed(container: Int, position: Int)

    /// At a byte offset in the file, written as `N G obj`.
    case direct(offset: Int, generation: Int)

    /// The generation the record names; an object in a stream is
    /// generation zero.
    internal var generation: Int {
      switch self {
      case .compressed:
        return 0
      case .direct(_, let generation):
        return generation
      }
    }
  }

  /// One historical in-use object entry observed anywhere in the
  /// cross-reference chain, retained even when a newer revision frees
  /// or redefines the object number.
  internal struct HistoricalObject: Equatable, Hashable, Sendable {
    /// The indirect object's number.
    internal let number: Int

    /// Where that revision placed the object.
    internal let location: ObjectLocation
  }

  /// One object a section accounts for.
  ///
  /// A free record carries no location, and claims its number so
  /// older sections' copies stay shadowed.
  internal struct SectionRecord {
    /// The object's number.
    internal let number: Int

    /// Where the object lives, or nil for a free record.
    internal let location: ObjectLocation?
  }

  /// One parsed cross-reference section.
  internal struct Section {
    /// The objects the section accounts for, in written order.
    internal let records: [SectionRecord]

    /// The trailer dictionary - for a stream section, the stream's
    /// own dictionary carries the trailer keys (ISO 32000-1 §7.5.8.2).
    internal let trailer: String

    /// Whether the section is a cross-reference stream.
    internal let isStream: Bool
  }

  /// Maximum /Prev hops followed before the chain is called broken.
  private static let maximumChainDepth = 64

  /// Object number to location, newest section winning.
  internal let locations: [Int: ObjectLocation]

  /// All distinct in-use `(number, location)` entries across the entire
  /// `/Prev` chain, ordered by object number and then oldest to newest.
  internal let historicalObjects: [HistoricalObject]

  /// The newest trailer dictionary, as written.
  internal let trailer: String

  /// The offset the file's last `startxref` names.
  internal let previousStartXref: Int

  /// Whether the newest section is a stream, which decides the shape
  /// of the section an update appends: readers of such a file have
  /// already committed to following streams (ISO 32000-1 §7.5.8).
  internal let newestSectionIsStream: Bool

  /// An unsigned integer value of a dictionary key, when present.
  internal static func integer(named key: String, in dictionary: String) -> Int? {
    guard
      let syntax = try? PdfValidationStore.DictionarySyntax.loose(dictionary),
      let entry = syntax.entry(named: Self.normalizedKey(key))
    else {
      return nil
    }
    return PdfValidationStore.TypedValues.unsignedInteger(
      in: syntax.value(of: entry)
    )
  }

  /// The object number of an indirect reference value, when the key
  /// holds a complete `N G R` reference.
  internal static func reference(
    named key: String,
    in dictionary: String
  ) -> Int? {
    Self.fullReference(named: key, in: dictionary)?.number
  }

  /// The `(number, generation)` pair of an indirect reference value,
  /// when the key holds a complete `N G R` reference.
  internal static func fullReference(
    named key: String,
    in dictionary: String
  ) -> PdfValidationStore.StoreReference? {
    guard
      let syntax = try? PdfValidationStore.DictionarySyntax.loose(dictionary),
      let entry = syntax.entry(named: Self.normalizedKey(key)),
      let parsed = try? PdfValidationStore.ValueParser.reference(
        in: syntax.value(of: entry)
      )
    else {
      return nil
    }
    return parsed
  }

  /// The integer array value of a dictionary key, empty when the key is
  /// absent or its value is not an array of unsigned decimal integers
  /// that each fit in `Int`.
  internal static func integerArray(
    named key: String,
    in dictionary: String
  ) -> [Int] {
    guard
      let syntax = try? PdfValidationStore.DictionarySyntax.loose(dictionary),
      let entry = syntax.entry(named: Self.normalizedKey(key))
    else {
      return []
    }
    return PdfValidationStore.TypedValues.unsignedIntegerArray(
      in: syntax.value(of: entry)
    )
  }

  /// Parses the chain from the end of the file.
  internal static func parse(_ document: Data) throws -> Self {
    let bytes = PdfBytes(document)
    guard bytes.starts(with: PdfValues.filePrefix) else {
      throw PdfSigningError.notAPdf
    }
    guard
      let startXref = Self.startXref(in: bytes),
      startXref >= 0,
      startXref < bytes.count
    else {
      throw PdfSigningError.structureUnreadable
    }
    let sections = try Self.sectionsChain(
      in: bytes, startingAt: startXref, limit: Self.maximumChainDepth
    )
    guard let newest = sections.first else {
      throw PdfSigningError.structureUnreadable
    }
    let collected = Self.liveLocations(in: sections)
    let history = try Self.historicalRecords(in: sections)
    return Self(
      locations: collected,
      historicalObjects: history,
      trailer: newest.trailer,
      previousStartXref: startXref,
      newestSectionIsStream: newest.isStream
    )
  }

  /// Strips a leading slash so callers may pass either `"/Root"` or
  /// `"Root"`.
  internal static func normalizedKey(_ key: String) -> String {
    key.hasPrefix("/") ? String(key.dropFirst()) : key
  }

  /// Refuses any trailer or cross-reference dictionary carrying `/Encrypt`.
  internal static func rejectIfEncrypted(in dictionary: String) throws {
    let syntax = try PdfValidationStore.DictionarySyntax(dictionary)
    guard syntax.entry(named: Self.normalizedKey(PdfValues.encryptKey)) == nil
    else {
      throw PdfSigningError.encrypted
    }
  }

  /// The byte offset the last `startxref` names.
  private static func startXref(in bytes: PdfBytes) -> Int? {
    guard let found = bytes.lastRange(of: PdfValues.startXrefKeyword) else {
      return nil
    }
    return bytes.decimal(at: bytes.skippingWhitespace(from: found.upperBound))
  }
}
