// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// The ByteRange hole is this dictionary's own `/Contents`, padded
/// with zeros, and a range ends where a revision ends (ISO 32000-1
/// clauses 12.8.1 and 7.5.5).
@Suite
internal struct PdfSignatureReaderTests {
  /// A DER element standing in for a CMS signature.
  private static let carried = DerEncoder.sequence([
    DerEncoder.octetString(Data("synthetic signature".utf8))
  ])

  /// The ByteRange array as the signer writes it.
  private static let byteRangePrefix = Data(PdfIncrementalSigner.byteRangeArrayPrefix.utf8)

  /// Bytes of the four fixed-width ByteRange fields and their separators.
  private static let byteRangeFieldsLength =
    (PdfValues.byteRangeDigits + Self.separatorLength) * PdfValues.byteRangeFieldCount

  /// The space before each ByteRange field.
  private static let separatorLength = 1

  /// Signatures in a twice-signed document.
  private static let twiceSignedCount = 2

  /// The closing `>` of the hex hole.
  private static let closingBracketLength = 1

  /// One position before another.
  private static let onePosition = 1

  /// A hex digit that is not padding.
  private static let nonZeroHexDigit = UInt8(ascii: "1")

  /// End-of-line spellings that may follow `%%EOF`.
  private static let endOfLines = ["", "\n", "\r", "\r\n"]

  /// A once-signed minimal PDF.
  private static func signedOnce() throws -> Data {
    try QualifiedDocumentCmsTests.placeholder().filled(with: Self.carried)
  }

  /// `document` signed again in a new revision.
  private static func signedTwice() throws -> Data {
    let second = try PdfIncrementalSigner.prepare(
      try Self.signedOnce(),
      revision: .signature(
        PdfIncrementalSigner.SignatureClaim(
          signedAt: Date(timeIntervalSince1970: 0), reason: nil, location: nil
        )
      )
    )
    return try second.filled(with: Self.carried)
  }

  /// Every offset at which `needle` starts in `document`.
  private static func offsets(of needle: Data, in document: Data) -> [Int] {
    var found: [Int] = []
    var from = document.startIndex
    while let range = document.range(of: needle, in: from..<document.endIndex) {
      found.append(range.lowerBound)
      from = range.upperBound
    }
    return found
  }

  /// The length of the end-of-line after the final `%%EOF`.
  private static func endOfLineLength(_ document: Data) -> Int {
    let marker = Data(PdfValues.endOfFileMarker.utf8)
    guard let range = document.range(of: marker, options: .backwards) else { return .zero }
    return document.count - range.upperBound
  }

  @Test
  internal func preparedSignatureReadsAndEndsItsRevision() throws {
    let found = try PdfSignatureReader.signatures(in: try Self.signedOnce())
    try #require(found.count == 1)
    #expect(found[0].cms == Self.carried)
    #expect(found[0].endsRevision)
    #expect(found[0].coversWholeDocument)
  }

  @Test
  internal func byteRangeNamingAnotherDictionarysHoleIsRefused() throws {
    var document = try Self.signedTwice()
    let arrays = Self.offsets(of: Self.byteRangePrefix, in: document)
    try #require(arrays.count == Self.twiceSignedCount)
    #expect(try PdfSignatureReader.signatures(in: document).count == Self.twiceSignedCount)
    let fields = Self.byteRangeFieldsLength
    let first = arrays[0] + Self.byteRangePrefix.count
    let last = arrays[arrays.count - Self.onePosition] + Self.byteRangePrefix.count
    document.replaceSubrange(last..<(last + fields), with: document[first..<(first + fields)])
    #expect(throws: PdfSignatureReader.Failure.malformedByteRange) {
      try PdfSignatureReader.signatures(in: document)
    }
  }

  @Test
  internal func nonZeroBytesAfterTheDerAreRefused() throws {
    var document = try Self.signedOnce()
    let found = try PdfSignatureReader.signatures(in: document)
    try #require(found.count == 1)
    let lastDigit =
      found[0].signedSpans.secondSpanStart - Self.closingBracketLength - Self.onePosition
    document[lastDigit] = Self.nonZeroHexDigit
    #expect(throws: PdfSignatureReader.Failure.malformedContents) {
      try PdfSignatureReader.signatures(in: document)
    }
  }

  @Test
  internal func rangeEndingAtEndOfFileMarkerEndsARevision() {
    for endOfLine in Self.endOfLines {
      let revision = Data(("startxref" + PdfValues.endOfFileMarker + endOfLine).utf8)
      #expect(PdfSignatureReader.endsRevision(revision))
    }
  }

  @Test
  internal func rangeCutShortOfEndOfFileMarkerDoesNotEndARevision() throws {
    let document = try Self.signedOnce()
    #expect(PdfSignatureReader.endsRevision(document))
    let marker = PdfValues.endOfFileMarker.count
    for cut in Self.onePosition...marker {
      let trimmed = document.prefix(document.count - Self.endOfLineLength(document) - cut)
      #expect(!PdfSignatureReader.endsRevision(trimmed))
    }
  }
}
