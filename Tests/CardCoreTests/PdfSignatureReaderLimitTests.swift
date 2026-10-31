// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// ByteRange values are unsigned integers that fit, and the reader maps
/// no more than its ceiling of a document.
@Suite
internal struct PdfSignatureReaderLimitTests {
  /// A DER element standing in for a CMS signature.
  private static let carried = DerEncoder.sequence([
    DerEncoder.octetString(Data("synthetic signature".utf8))
  ])

  /// The ByteRange array as the signer writes it.
  private static let byteRangePrefix = Data(PdfIncrementalSigner.byteRangeArrayPrefix.utf8)

  /// The space before each ByteRange field.
  private static let separatorLength = 1

  /// The minus sign that makes a ByteRange field negative.
  private static let minus = "-"

  /// A decimal value one digit wider than any Int.
  private static let overflowingValue = String(Int.max) + "0"

  /// Bytes around a document inside a larger buffer.
  private static let surroundingText = "surrounding bytes"

  /// One byte fewer than a document holds.
  private static let oneByte = 1

  /// A once-signed minimal PDF.
  private static func signedOnce() throws -> Data {
    try QualifiedDocumentCmsTests.placeholder().filled(with: Self.carried)
  }

  @Test
  internal func negativeByteRangeEntryIsRefused() throws {
    var document = try Self.signedOnce()
    let array = try #require(document.range(of: Self.byteRangePrefix))
    // The last field keeps its width: its first digit becomes a sign.
    let fieldsLength =
      (PdfValues.byteRangeDigits + Self.separatorLength) * PdfValues.byteRangeFieldCount
    let lastFieldStart = array.upperBound + fieldsLength - PdfValues.byteRangeDigits
    document.replaceSubrange(
      lastFieldStart..<(lastFieldStart + Self.minus.utf8.count), with: Data(Self.minus.utf8))
    #expect(throws: PdfSignatureReader.Failure.malformedByteRange) {
      try PdfSignatureReader.signatures(in: document)
    }
  }

  @Test
  internal func signedAndOverflowingIntegersAreNotAnIntegerArray() {
    let values = ["0", Self.minus + "1", "2", "3"].joined(separator: " ")
    #expect(PdfDocumentIndex.integerArray(named: "/A", in: "/A [\(values)]").isEmpty)
    let huge = ["0", Self.overflowingValue, "2", "3"].joined(separator: " ")
    #expect(PdfDocumentIndex.integerArray(named: "/A", in: "/A [\(huge)]").isEmpty)
    let plain = ["0", "1", "2", "3"].joined(separator: " ")
    #expect(
      PdfDocumentIndex.integerArray(named: "/A", in: "/A [\(plain)]").count
        == PdfValues.byteRangeFieldCount)
  }

  @Test
  internal func documentOverTheCeilingIsRefused() throws {
    let document = try Self.signedOnce()
    #expect(throws: PdfSignatureReader.Failure.documentTooLarge) {
      try PdfSignatureReader.signatures(
        in: document, maximumByteCount: document.count - Self.oneByte)
    }
    #expect(
      try PdfSignatureReader.signatures(in: document, maximumByteCount: document.count).count
        == 1)
  }

  @Test
  internal func documentSlicedFromLargerDataReads() throws {
    let document = try Self.signedOnce()
    let surrounding = Data(Self.surroundingText.utf8)
    let larger = surrounding + document + surrounding
    let slice = larger[surrounding.count..<(surrounding.count + document.count)]
    try #require(slice.startIndex != .zero)

    let found = try PdfSignatureReader.signatures(in: slice)
    #expect(found.count == 1)
    #expect(found.first?.cms == Self.carried)
    #expect(found.first?.coversWholeDocument == true)
  }
}
