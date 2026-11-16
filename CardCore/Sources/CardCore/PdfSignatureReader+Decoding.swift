// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Byte-range verification and `/Contents` hex-hole decoding for
/// `PdfSignatureReader`.
extension PdfSignatureReader {
  /// A signature `/ByteRange` declares two spans as four integers.
  private static let byteRangeEntryCount = 4

  /// The value of the first hex digit above nine.
  private static let hexLetterBase: UInt8 = 10

  /// The byte every unused position of the decoded hole holds.
  private static let contentsPadding: UInt8 = 0

  /// The end-of-line spellings that may follow `%%EOF`, longest first.
  private static let endOfLineSpellings: [[UInt8]] = [
    [PdfValues.carriageReturnByte, PdfValues.lineFeedByte],
    [PdfValues.lineFeedByte],
    [PdfValues.carriageReturnByte],
  ]

  /// Whether `signed` ends with `%%EOF` and at most one end-of-line.
  internal static func endsRevision(_ signed: Data) -> Bool {
    let bytes = [UInt8](signed)
    let markerEnd =
      Self.endOfLineSpellings
      .first { spelling in
        bytes.count >= spelling.count
          && bytes.suffix(spelling.count).elementsEqual(spelling)
      }
      .map { bytes.dropLast($0.count) } ?? bytes[...]
    let marker = Array(PdfValues.endOfFileMarker.utf8)
    return markerEnd.count >= marker.count
      && markerEnd.suffix(marker.count).elementsEqual(marker)
  }

  /// Where a dictionary value sits in the file, for a direct indirect
  /// object whose header matches `(objectNumber, generation)`.
  internal static func fileRange(
    of valueRange: Range<Int>,
    body: String,
    objectNumber: Int,
    location: PdfDocumentIndex.ObjectLocation,
    in document: Data
  ) throws -> Range<Int> {
    guard case .direct(let offset, let generation) = location else {
      throw Failure.malformedContents
    }
    let bytes = PdfBytes(document)
    guard
      let headerEnd = bytes.objectHeaderEnd(
        at: offset,
        expectedNumber: objectNumber,
        expectedGeneration: generation
      ),
      let bodyBytes = body.data(using: .isoLatin1)
    else {
      throw Failure.malformedContents
    }
    let bodyStart = bytes.skippingWhitespace(from: headerEnd)
    guard
      bodyStart <= bytes.count - bodyBytes.count,
      bytes.data(in: bodyStart..<(bodyStart + bodyBytes.count)) == bodyBytes
    else {
      throw Failure.malformedContents
    }
    return
      (bodyStart + valueRange.lowerBound)..<(bodyStart + valueRange.upperBound)
  }

  /// Validates `/ByteRange` and `/Contents` and constructs a
  /// `FoundSignature`.
  internal static func signature(
    declaredBy body: String,
    syntax: PdfValidationStore.DictionarySyntax,
    contentsInFile: Range<Int>,
    in document: Data
  ) throws -> FoundSignature {
    let range = PdfDocumentIndex.integerArray(named: "ByteRange", in: body)
    var entries = range.makeIterator()
    guard
      range.count == Self.byteRangeEntryCount,
      let firstStart = entries.next(),
      let holeStart = entries.next(),
      let holeEnd = entries.next(),
      let tailLength = entries.next(),
      firstStart == 0,
      holeStart > 0,
      holeEnd > holeStart,
      tailLength >= 0,
      holeEnd <= document.count,
      tailLength <= document.count - holeEnd,
      holeStart..<holeEnd == contentsInFile
    else {
      throw Failure.malformedByteRange
    }
    let end = holeEnd + tailLength
    let placeholder = PdfSignaturePlaceholder(
      document: document.prefix(end),
      contentsOpen: holeStart,
      secondSpanStart: holeEnd,
      capacity: 0
    )
    return FoundSignature(
      cms: try Self.contents(inHole: holeStart..<holeEnd, of: document),
      subFilter: Self.subFilter(in: syntax),
      signedSpans: placeholder,
      coversWholeDocument: end == document.count,
      endsRevision: Self.endsRevision(document.prefix(end))
    )
  }

  /// The declared `/SubFilter`, `.other` when absent or not a `/Name`.
  private static func subFilter(
    in syntax: PdfValidationStore.DictionarySyntax
  ) -> PdfSubFilter {
    guard
      let entry = syntax.entry(named: "SubFilter"),
      let decoded = PdfValidationStore.TypedValues.decodedName(
        in: syntax.value(of: entry)
      )
    else {
      return .other
    }
    return PdfSubFilter(name: String(decoded.dropFirst()))
  }

  /// Decodes the hex string filling the hole and trims trailing zero
  /// padding after the single DER element.
  private static func contents(
    inHole hole: Range<Int>,
    of document: Data
  ) throws -> Data {
    guard
      document[hole.lowerBound] == UInt8(ascii: "<"),
      document[hole.upperBound - 1] == UInt8(ascii: ">")
    else {
      throw Failure.malformedContents
    }
    var decoded = Data()
    var pending: UInt8?
    for cursor in (hole.lowerBound + 1)..<(hole.upperBound - 1) {
      guard let value = Self.hexValue(of: document[cursor]) else {
        throw Failure.malformedContents
      }
      if let high = pending {
        decoded.append(high << PdfValues.hexDigitBits | value)
        pending = nil
      } else {
        pending = value
      }
    }
    guard pending == nil else { throw Failure.malformedContents }
    var reader = DerReader(decoded)
    guard let element = reader.next() else {
      throw Failure.malformedContents
    }
    guard
      decoded[element.raw.upperBound...].allSatisfy({ byte in
        byte == Self.contentsPadding
      })
    else {
      throw Failure.malformedContents
    }
    return decoded.subdata(in: element.raw)
  }

  /// Decodes one ASCII hexadecimal digit.
  private static func hexValue(of byte: UInt8) -> UInt8? {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"):
      byte - UInt8(ascii: "0")

    case UInt8(ascii: "A")...UInt8(ascii: "F"):
      byte - UInt8(ascii: "A") + Self.hexLetterBase

    case UInt8(ascii: "a")...UInt8(ascii: "f"):
      byte - UInt8(ascii: "a") + Self.hexLetterBase

    default:
      nil
    }
  }
}
