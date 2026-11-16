// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One indirect stream object: its dictionary and its decoded payload
/// (ISO 32000-1 §7.3.8 streams, §7.4.4 FlateDecode and predictors).
///
/// Serves the stream shapes the cross-reference chain and validation
/// store name: cross-reference streams, object streams, and raw evidence
/// streams.
internal struct PdfStreamObject {
  /// Byte spans of a stream object inside a PDF file.
  internal struct RawStreamSpan {
    /// The balanced stream dictionary text.
    internal let dictionary: String

    /// The raw (undecoded) stream payload range.
    internal let payloadRange: Range<Int>

    /// The start of the closing `endobj` keyword.
    internal let endObjectStart: Int
  }

  /// The stream dictionary, as written.
  internal let dictionary: String

  /// The payload with its filter and predictor undone.
  internal let payload: Data

  /// Parses `N G obj << ... >> stream ... endstream endobj` at `offset`.
  internal static func parse(
    in bytes: PdfBytes,
    at offset: Int
  ) throws -> Self {
    try Self.parse(
      in: bytes,
      at: offset,
      expectedNumber: nil,
      expectedGeneration: nil,
      resolveLength: nil
    )
  }

  /// Parses `N G obj << ... >> stream ... endstream endobj` at `offset`,
  /// verifying the indirect object header when an object identity is
  /// supplied.
  internal static func parse(
    in bytes: PdfBytes,
    at offset: Int,
    expectedNumber: Int?,
    expectedGeneration: Int?
  ) throws -> Self {
    try Self.parse(
      in: bytes,
      at: offset,
      expectedNumber: expectedNumber,
      expectedGeneration: expectedGeneration,
      resolveLength: nil
    )
  }

  /// Parses `N G obj << ... >> stream ... endstream endobj` at `offset`,
  /// resolving indirect `/Length` references with `resolveLength` when
  /// provided.
  internal static func parse(
    in bytes: PdfBytes,
    at offset: Int,
    expectedNumber: Int?,
    expectedGeneration: Int?,
    resolveLength: ((PdfValidationStore.StoreReference) -> Int?)?
  ) throws -> Self {
    let span = try Self.rawSpan(
      in: bytes,
      at: offset,
      expectedNumber: expectedNumber,
      expectedGeneration: expectedGeneration,
      resolveLength: resolveLength
    )
    let raw = bytes.data(in: span.payloadRange)
    let decoded = try Self.decoded(raw, dictionary: span.dictionary)
    return Self(dictionary: span.dictionary, payload: decoded)
  }

  /// Locates a stream object's dictionary, payload span, and `endobj`
  /// boundary without inflating its payload.
  internal static func rawSpan(
    in bytes: PdfBytes,
    at offset: Int,
    expectedNumber: Int?,
    expectedGeneration: Int?,
    resolveLength: ((PdfValidationStore.StoreReference) -> Int?)?
  ) throws -> RawStreamSpan {
    guard
      let headerEnd = bytes.objectHeaderEnd(
        at: offset,
        expectedNumber: expectedNumber,
        expectedGeneration: expectedGeneration
      ),
      let content = bytes.balancedDictionary(from: headerEnd)
    else {
      throw PdfSigningError.structureUnreadable
    }
    let keywordAt = bytes.skippingTrivia(from: content.end)
    guard bytes.hasKeywordToken(PdfValues.streamKeyword, at: keywordAt) else {
      throw PdfSigningError.structureUnreadable
    }
    let payloadRange = try Self.payloadRange(
      in: bytes,
      streamKeywordEnd: keywordAt + PdfValues.streamKeyword.utf8.count,
      dictionary: content.text,
      resolveLength: resolveLength
    )
    let endStreamAt = bytes.skippingTrivia(from: payloadRange.upperBound)
    guard bytes.hasKeywordToken(PdfValues.endStreamKeyword, at: endStreamAt)
    else {
      throw PdfSigningError.structureUnreadable
    }
    let endObjAt = bytes.skippingTrivia(
      from: endStreamAt + PdfValues.endStreamKeyword.utf8.count
    )
    guard bytes.hasKeywordToken(PdfValues.endObjectKeyword, at: endObjAt) else {
      throw PdfSigningError.structureUnreadable
    }
    return RawStreamSpan(
      dictionary: content.text,
      payloadRange: payloadRange,
      endObjectStart: endObjAt
    )
  }

  /// The payload with its filter chain and predictor undone.
  internal static func decoded(
    _ raw: Data,
    dictionary: String
  ) throws -> Data {
    let syntax = try PdfValidationStore.DictionarySyntax(dictionary)
    let names = try Self.filterNames(in: syntax)
    let inflated: Data
    if names.isEmpty {
      inflated = raw
    } else if names == [PdfValues.flateFilterName] {
      guard
        let out = FlateDecoder.decoded(
          raw, limit: PdfValues.inflatedStreamLimit
        )
      else {
        throw PdfSigningError.structureUnreadable
      }
      inflated = out
    } else {
      throw PdfSigningError.crossReferenceStreamUnsupported
    }
    return try Self.unpredicted(inflated, syntax: syntax)
  }

  /// Resolves the raw stream payload span after `stream` + EOL.
  private static func payloadRange(
    in bytes: PdfBytes,
    streamKeywordEnd: Int,
    dictionary: String,
    resolveLength: ((PdfValidationStore.StoreReference) -> Int?)?
  ) throws -> Range<Int> {
    var dataStart = streamKeywordEnd
    if bytes.hasKeyword("\r", at: dataStart) { dataStart += 1 }
    if bytes.hasKeyword("\n", at: dataStart) { dataStart += 1 }
    if let length = try Self.declaredLength(
      in: dictionary, resolveLength: resolveLength
    ) {
      guard length >= 0, dataStart <= bytes.count - length else {
        throw PdfSigningError.structureUnreadable
      }
      return dataStart..<(dataStart + length)
    }
    guard
      let endStreamStart = Self.closingEndStream(in: bytes, from: dataStart)
    else {
      throw PdfSigningError.structureUnreadable
    }
    var dataEnd = endStreamStart
    if dataEnd > dataStart, bytes.hasKeyword("\n", at: dataEnd - 1) {
      dataEnd -= 1
    }
    if dataEnd > dataStart, bytes.hasKeyword("\r", at: dataEnd - 1) {
      dataEnd -= 1
    }
    return dataStart..<dataEnd
  }

  /// Scans for an `endstream` keyword token that is followed only by
  /// trivia before `endobj`.
  private static func closingEndStream(
    in bytes: PdfBytes,
    from start: Int
  ) -> Int? {
    var cursor = start
    while let found = bytes.firstRange(
      of: PdfValues.endStreamKeyword, from: cursor
    ) {
      let endObjAt = bytes.skippingTrivia(from: found.upperBound)
      if bytes.hasKeywordToken(PdfValues.endStreamKeyword, at: found.lowerBound),
        bytes.hasKeywordToken(PdfValues.endObjectKeyword, at: endObjAt)
      {
        return found.lowerBound
      }
      cursor = found.lowerBound + 1
    }
    return nil
  }

  /// Resolves direct or indirect `/Length` when possible; throws when
  /// `/Length` is malformed or unresolvable.
  private static func declaredLength(
    in dictionary: String,
    resolveLength: ((PdfValidationStore.StoreReference) -> Int?)?
  ) throws -> Int? {
    let syntax = try PdfValidationStore.DictionarySyntax(dictionary)
    guard let entry = syntax.entry(named: "Length") else { return nil }
    let raw = syntax.value(of: entry)
    if let direct = PdfValidationStore.TypedValues.unsignedInteger(in: raw) {
      return direct
    }
    if let reference = try? PdfValidationStore.ValueParser.reference(in: raw) {
      guard let resolveLength else { return nil }
      guard let resolved = resolveLength(reference) else {
        throw PdfSigningError.structureUnreadable
      }
      return resolved
    }
    throw PdfSigningError.structureUnreadable
  }

  /// The decoded names the `/Filter` entry carries, in order.
  private static func filterNames(
    in syntax: PdfValidationStore.DictionarySyntax
  ) throws -> [String] {
    guard let entry = syntax.entry(named: "Filter") else { return [] }
    guard
      let names = try? PdfValidationStore.TypedValues.decodedNameList(
        in: syntax.value(of: entry)
      )
    else {
      throw PdfSigningError.structureUnreadable
    }
    return names
  }
}
