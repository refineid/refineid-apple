// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Locates the signatures of an existing PDF (ISO 32000-1 section 12.8).
///
/// The byte ranges declared by each signature dictionary define the two
/// signed spans and, between them, the hex hole carrying the CMS; the
/// reader trusts the declaration only after checking it against the
/// file's actual bytes.
public enum PdfSignatureReader {
  /// One signature found in the document.
  public struct FoundSignature: Sendable {
    /// The CMS ContentInfo carried in the hole, padding removed.
    public let cms: Data

    /// The declared /SubFilter name, empty when absent.
    public let subFilter: String

    /// The two declared byte-range spans.
    internal let signedSpans: PdfSignaturePlaceholder

    /// Whether the spans cover the entire file, which the final
    /// signature of a document always does.
    public let coversWholeDocument: Bool

    /// The digest of the two declared byte-range spans.
    public func byteRangeDigest(_ algorithm: DocumentDigestAlgorithm) -> Data {
      signedSpans.digest(algorithm)
    }
  }

  /// Why a located signature could not be read.
  public enum Failure: Error, Sendable {
    case malformedByteRange
    case malformedContents
  }

  /// A signature /ByteRange declares two spans as four integers.
  private static let byteRangeEntryCount = 4

  /// The value of the first hex digit above nine.
  private static let hexLetterBase: UInt8 = 10

  /// Every readable signature in the document, in object order.
  ///
  /// Objects without both /ByteRange and /Contents are not signatures
  /// and are skipped; a signature candidate whose declaration does not
  /// match the file throws instead of degrading into a partial answer.
  public static func signatures(
    in document: Data
  ) throws -> [FoundSignature] {
    let index = try PdfDocumentIndex.parse(document)
    var found: [FoundSignature] = []
    for number in index.locations.keys.sorted() {
      guard
        let body = index.body(of: number, in: document),
        body.contains("/ByteRange"), body.contains("/Contents")
      else { continue }
      found.append(try signature(declaredBy: body, in: document))
    }
    return found
  }

  private static func signature(
    declaredBy body: String,
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
      holeEnd + tailLength <= document.count
    else {
      throw Failure.malformedByteRange
    }
    // The declared spans end where this signature's revision ended;
    // later revisions are not covered and must not be digested.
    let placeholder = PdfSignaturePlaceholder(
      document: document.prefix(holeEnd + tailLength),
      contentsOpen: holeStart,
      secondSpanStart: holeEnd,
      capacity: 0
    )
    let subFilter = subFilterName(in: body)
    return FoundSignature(
      cms: try contents(inHole: holeStart..<holeEnd, of: document),
      subFilter: subFilter,
      signedSpans: placeholder,
      coversWholeDocument: holeEnd + tailLength == document.count
    )
  }

  /// The declared /SubFilter name without its solidus, empty when
  /// absent or unreadable.
  private static func subFilterName(in body: String) -> String {
    guard
      let syntax = try? PdfValidationStore.DictionarySyntax(body),
      let entry = syntax.entry(named: "SubFilter")
    else {
      return ""
    }
    let value = syntax.value(of: entry)
    guard value.hasPrefix("/") else { return value }
    return String(value.dropFirst())
  }

  /// Decodes the hex string filling the hole and trims it to the one
  /// DER element it carries.
  private static func contents(
    inHole hole: Range<Int>,
    of document: Data
  ) throws -> Data {
    let bytes = PdfBytes(document)
    let opening = bytes.skippingWhitespace(from: hole.lowerBound)
    guard
      opening < hole.upperBound,
      document[opening] == UInt8(ascii: "<")
    else {
      throw Failure.malformedContents
    }
    var decoded = Data()
    var pending: UInt8?
    var cursor = opening + 1
    while cursor < hole.upperBound {
      let byte = document[cursor]
      cursor += 1
      if byte == UInt8(ascii: ">") { break }
      guard let value = hexValue(of: byte) else {
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
    return decoded.subdata(in: element.raw)
  }

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
