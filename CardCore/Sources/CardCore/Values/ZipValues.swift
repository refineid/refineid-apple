// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The ZIP structural values the ASiC-E container writer emits.
///
/// From the PKWARE APPNOTE, held to the ISO/IEC 21320-1 profile:
/// stored entries only, one volume, no encryption.
internal enum ZipValues {
  /// Local file header signature, `PK\x03\x04` little-endian
  /// (APPNOTE 4.3.7).
  internal static let localHeaderSignature: UInt32 = 0x0403_4B50

  /// Central directory file header signature, `PK\x01\x02`
  /// (APPNOTE 4.3.12).
  internal static let centralHeaderSignature: UInt32 = 0x0201_4B50

  /// End of central directory signature, `PK\x05\x06` (APPNOTE 4.3.16).
  internal static let endOfDirectorySignature: UInt32 = 0x0605_4B50

  /// Minimum version needed to extract: 2.0, meaning stored or deflated
  /// (APPNOTE 4.4.3.2).
  internal static let versionNeeded: UInt16 = 20

  /// Version made by: Unix (3 in the high byte) and specification 2.0
  /// (APPNOTE 4.4.2.2).
  internal static let versionMadeBy: UInt16 = 0x0314

  /// External attributes for regular files with standard permissions (0100644 << 16).
  internal static let regularFileExternalAttributes: UInt32 = 0x81A4_0000

  /// Compression method 0: stored (APPNOTE 4.4.5).
  internal static let methodStored: UInt16 = 0

  /// General-purpose bit 11: the entry name is UTF-8 (APPNOTE 4.4.4).
  internal static let utf8NameFlag: UInt16 = 0x0800

  /// CRC-32 polynomial in reflected form (IEEE 802.3, APPNOTE 4.4.7).
  internal static let crcPolynomial: UInt32 = 0xEDB8_8320

  /// Bits per input byte in the bitwise CRC computation.
  internal static let crcBitsPerByte = 8

  /// Local file header length before the entry name begins.
  ///
  /// A reader identifies an ASiC container by looking exactly past
  /// here.
  internal static let localHeaderLength = 30

  /// Compression method 8: deflated (APPNOTE 4.4.5).
  internal static let methodDeflated: UInt16 = 8

  /// Fixed length of the End of Central Directory record (APPNOTE 4.3.16).
  internal static let eocdRecordLength = 22

  /// Maximum length to search backwards for EOCD record (22 bytes fixed + 65535 comment).
  internal static let eocdSearchLimit = 65_557

  /// Central directory header length before filename begins (APPNOTE 4.3.12).
  internal static let centralDirectoryHeaderLength = 46

  /// Byte offset of total entry count within EOCD record.
  internal static let eocdEntryCountOffset = 10

  /// Byte offset of central directory size within EOCD record.
  internal static let eocdDirectorySizeOffset = 12

  /// Byte offset of central directory start position within EOCD record.
  internal static let eocdDirectoryOffsetOffset = 16

  /// Byte offset of compression method in central directory header.
  internal static let cdMethodOffset = 10

  /// Byte offset of CRC-32 in central directory header.
  internal static let cdCrcOffset = 16

  /// Byte offset of compressed size in central directory header.
  internal static let cdCompressedSizeOffset = 20

  /// Byte offset of uncompressed size in central directory header.
  internal static let cdUncompressedSizeOffset = 24

  /// Byte offset of file name length in central directory header.
  internal static let cdNameLengthOffset = 28

  /// Byte offset of extra field length in central directory header.
  internal static let cdExtraLengthOffset = 30

  /// Byte offset of comment length in central directory header.
  internal static let cdCommentLengthOffset = 32

  /// Byte offset of local header offset in central directory header.
  internal static let cdLocalHeaderOffset = 42

  /// Byte offset of file name length in local file header.
  internal static let localNameLengthOffset = 26

  /// Byte offset of extra field length in local file header.
  internal static let localExtraLengthOffset = 28

  /// Byte offset of the first local file header in an archive.
  internal static let firstEntryOffset = 0

  /// Largest number of bytes the reader accepts for one entry, and for
  /// all entries together, compressed or not.
  ///
  /// Checked against the declared sizes before any allocation; the same
  /// bound refineid-core's container reader applies.
  internal static let maximumEntryByteCount = 512 << 20

  /// Negative window bits for zlib raw DEFLATE decompressor (RFC 1951).
  internal static let zlibRawDeflateWindowBits: Int32 = -15

  /// The extra-field length of a local header carrying no extra field.
  internal static let emptyExtraFieldLength = 0
}
