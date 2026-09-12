// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The dedicated home for PDF syntax constants used by signing.
///
/// Sources: ISO 32000-1 (PDF 1.7) for file structure and the
/// signature dictionary, ETSI EN 319 142-1 for the PAdES entries.
internal enum PdfValues {
  /// The two base-14 fonts a stamp draws with.
  ///
  /// Declared inside the page's resources rather than as objects of
  /// their own: they are standard, so nothing is embedded and nothing
  /// else refers to them. WinAnsi is what carries the accents of a
  /// French or Finnish name.
  /// How far the mark's edge sits from the page's edge: well into
  /// the margin, where it cannot crowd the text it sits beside.
  internal static let stampMargin = 8.0

  /// Clear space between one stamp and the next.
  internal static let stampGap = 6.0

  /// Room left around the mark inside its own box.
  ///
  /// A stroked ring straddles its radius - half the pen falls
  /// outside - and an appearance is clipped to its box, so a box
  /// sized to the radius shaves the ring flat wherever the two meet.
  internal static let stampBleed = 4.0

  /// Radii across a stamp, for stepping from one to the next.
  internal static let stampDiameters = 2.0

  /// The key naming a content stream as a stamp this program wrote.
  ///
  /// A reader ignores keys it does not know; the next signing counts
  /// them, so a second signer's mark stands beside the first rather
  /// than on it.
  internal static let stampMarker = "/RefineIDStamp"

  /// A4, for a page that states no box of its own.
  internal static let a4Width = 595.276
  internal static let a4Height = 841.89

  /// Numbers in a media box, and where each sits in it.
  internal static let boxCorners = 4
  internal static let boxLowerLeftX = 0
  internal static let boxLowerLeftY = 1
  internal static let boxUpperRightX = 2
  internal static let boxUpperRightY = 3

  /// The font entries alone, for merging into a page that already has
  /// a font dictionary.
  internal static let stampFontEntries =
    "/RfStampRegular << /Type /Font /Subtype /Type1 /BaseFont /Helvetica"
    + " /Encoding /WinAnsiEncoding >>"

  internal static let stampFonts =
    "<< " + Self.stampFontEntries + " >>"

  /// Every PDF begins with this.
  internal static let filePrefix = "%PDF-"

  /// The keyword whose last occurrence names the newest cross-
  /// reference table (ISO 32000-1 §7.5.5).
  internal static let startXrefKeyword = "startxref"

  /// The cross-reference table keyword.
  internal static let xrefKeyword = "xref"

  /// The trailer keyword.
  internal static let trailerKeyword = "trailer"

  /// The end-of-file marker.
  internal static let endOfFileMarker = "%%EOF"

  /// The type name of a cross-reference stream (ISO 32000-1 §7.5.8).
  internal static let xrefStreamMarker = "/XRef"

  /// The object keyword opening an indirect object's body.
  internal static let objectKeyword = "obj"

  /// The keyword opening a stream's payload (ISO 32000-1 §7.3.8.1).
  internal static let streamKeyword = "stream"

  /// The keyword closing a stream's payload.
  internal static let endStreamKeyword = "endstream"

  /// The stream-dictionary key naming the payload's filter chain.
  internal static let filterKey = "/Filter"

  /// The one filter this reader decodes (ISO 32000-1 §7.4.4).
  internal static let flateFilterName = "FlateDecode"

  /// The hybrid trailer key naming the revision's cross-reference
  /// stream, whose entries are the authoritative copy
  /// (ISO 32000-1 §7.5.8.4).
  internal static let hybridStreamKey = "/XRefStm"

  /// Fields in one cross-reference stream entry: /W is three wide
  /// (ISO 32000-1 §7.5.8.2).
  internal static let xrefStreamFieldCount = 3

  /// The entry field holding the type code.
  internal static let entryTypeField = 0

  /// The entry field holding the offset or container number.
  internal static let entryFirstField = 1

  /// The entry field holding the generation or in-stream position.
  internal static let entrySecondField = 2

  /// Type code of a free entry (ISO 32000-1 Table 18).
  internal static let freeEntryType = 0

  /// Type code of an entry at a byte offset in the file.
  internal static let directEntryType = 1

  /// Type code of an entry inside an object stream.
  internal static let compressedEntryType = 2

  /// Width of the type field this writer emits.
  internal static let xrefStreamTypeWidth = 1

  /// Width of the offset field this writer emits.
  internal static let xrefStreamOffsetWidth = 4

  /// Width of the generation field this writer emits.
  internal static let xrefStreamGenerationWidth = 2

  /// The largest offset a four-byte field can address.
  internal static let xrefStreamOffsetLimit = 0xFFFF_FFFF

  /// Mask selecting one byte of a wider offset.
  internal static let byteMask = 0xFF

  /// The object-stream key naming where its first object begins
  /// (ISO 32000-1 §7.5.7).
  internal static let objectStreamFirstKey = "/First"

  /// The object-stream key counting the objects it carries.
  internal static let objectStreamCountKey = "/N"

  /// Tokens per pair in an object stream's leading table: an object
  /// number and its offset relative to /First.
  internal static let objectStreamPairTokens = 2

  /// The most bytes any one decoded stream may inflate to, bounding
  /// what a hostile document can make this reader allocate.
  internal static let inflatedStreamLimit = 67_108_864

  /// Characters in `<<` and `>>`.
  internal static let dictionaryMarkerLength: Int = 2

  /// The encryption dictionary key; an encrypted document is refused.
  internal static let encryptKey = "/Encrypt"

  /// Bytes of the hole reserved for the signature's CMS (ISO 32000-1
  /// §12.8.1: /Contents must be a fixed-length hex string).
  ///
  /// 48 KiB. A qualified signature with signature timestamps from
  /// several authorities was measured needing about 23 KiB, and the
  /// hole cannot be resized after the byte ranges are fixed, so this
  /// is deliberately generous: an overflow wastes a card signature,
  /// spare zero padding costs only file size.
  internal static let signatureCapacity: Int = 49_152

  /// Bytes reserved for a document timestamp's token, which carries
  /// one authority's answer and nothing else.
  internal static let timestampCapacity: Int = 16_384

  /// Digits reserved for each /ByteRange value; a fixed width is what
  /// lets the array be patched without moving anything.
  internal static let byteRangeDigits: Int = 10

  /// Tokens introducing one cross-reference subsection: its first
  /// object number and its entry count.
  internal static let subsectionHeaderTokens: Int = 2

  /// Tokens in one cross-reference entry: offset, generation, and the
  /// in-use or free flag.
  internal static let entryTokens: Int = 3

  /// Position of the in-use flag within an entry's tokens.
  internal static let entryFlagIndex: Int = 2

  /// The flag marking an in-use entry.
  internal static let inUseFlag = "n"

  /// The flag marking a free entry, which shadows older sections'
  /// copies of the same object.
  internal static let freeFlag = "f"

  /// The bytes PDF counts as whitespace (ISO 32000-1 §7.2.2).
  internal static let whitespaceBytes: Set<UInt8> = [
    Self.nullByte, Self.tabByte, Self.lineFeedByte, Self.formFeedByte,
    Self.carriageReturnByte, UInt8(ascii: " "),
  ]

  /// The null byte, which PDF counts as whitespace.
  internal static let nullByte: UInt8 = 0x00

  /// Horizontal tab.
  internal static let tabByte: UInt8 = 0x09

  /// Line feed.
  internal static let lineFeedByte: UInt8 = 0x0A

  /// Form feed.
  internal static let formFeedByte: UInt8 = 0x0C

  /// Carriage return; with a line feed it is the two-byte ending that
  /// makes character offsets differ from byte offsets.
  internal static let carriageReturnByte: UInt8 = 0x0D

  /// The radix cross-reference offsets are written in.
  internal static let decimalRadix: Int = 10

  /// Values in a /ByteRange array: two offset-length pairs, one for
  /// the span before the hole and one for the span after it.
  internal static let byteRangeFieldCount: Int = 4

  /// Maximum page-tree descents before the tree is called broken.
  internal static let pageTreeDepthLimit: Int = 32

  /// Uppercase hex digits: what /Contents is written in.
  internal static let hexDigits = "0123456789ABCDEF"

  /// Hex characters per byte: the hole holds two per reserved byte.
  internal static let hexCharactersPerByte: Int = 2

  /// Bits a hex digit carries, splitting a byte into its two nibbles.
  internal static let hexDigitBits: Int = 4

  /// Mask selecting one hex digit's nibble.
  internal static let hexDigitMask: UInt8 = 0x0F

  /// The angle brackets around the hex string, which the byte ranges
  /// exclude along with the hex itself.
  internal static let hexDelimiterCount: Int = 2
}
