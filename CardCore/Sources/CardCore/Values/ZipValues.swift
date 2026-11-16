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

  /// General-purpose bit 0 or 6: encrypted or strong-encrypted entry (APPNOTE 4.4.4).
  internal static let encryptedFlagsMask: UInt16 = 0x0041

  /// General-purpose bit 3: CRC and sizes also appear in a trailing data descriptor (APPNOTE 4.4.4).
  internal static let dataDescriptorFlag: UInt16 = 0x0008

  /// General-purpose bit 11: the entry name is UTF-8 (APPNOTE 4.4.4).
  internal static let utf8NameFlag: UInt16 = 0x0800

  /// Optional data descriptor signature, `PK\x07\x08` (APPNOTE 4.3.9.3).
  internal static let dataDescriptorSignature: UInt32 = 0x0807_4B50

  /// ZIP64 end of central directory locator signature, `PK\x06\x07` (APPNOTE 4.3.15).
  internal static let zip64LocatorSignature: UInt32 = 0x0706_4B50

  /// Length of the ZIP64 end of central directory locator (APPNOTE 4.3.15).
  internal static let zip64LocatorLength = 20

  /// Length of a data descriptor without the optional signature (APPNOTE 4.3.9).
  internal static let dataDescriptorLength = 12

  /// Length of a data descriptor starting with `dataDescriptorSignature` (APPNOTE 4.3.9.3).
  internal static let signedDataDescriptorLength = 16

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

  /// Byte offset of disk number within EOCD record.
  internal static let eocdDiskNumberOffset = 4

  /// Byte offset of central-directory start disk within EOCD record.
  internal static let eocdDirectoryDiskOffset = 6

  /// Byte offset of entry count on this disk within EOCD record.
  internal static let eocdDiskEntryCountOffset = 8

  /// Byte offset of total entry count within EOCD record.
  internal static let eocdEntryCountOffset = 10

  /// Byte offset of central directory size within EOCD record.
  internal static let eocdDirectorySizeOffset = 12

  /// Byte offset of central directory start position within EOCD record.
  internal static let eocdDirectoryOffsetOffset = 16

  /// Byte offset of archive comment length within EOCD record.
  internal static let eocdCommentLengthOffset = 20

  /// Byte offset of general-purpose bit flags in central directory header.
  internal static let cdFlagsOffset = 8

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

  /// Byte offset of disk number start in central directory header.
  internal static let cdDiskNumberOffset = 34

  /// Byte offset of external file attributes in central directory header.
  internal static let cdExternalAttributesOffset = 38

  /// Byte offset of local header offset in central directory header.
  internal static let cdLocalHeaderOffset = 42

  /// Byte offset of general-purpose bit flags in local file header.
  internal static let localFlagsOffset = 6

  /// Byte offset of compression method in local file header.
  internal static let localMethodOffset = 8

  /// Byte offset of CRC-32 in local file header.
  internal static let localCrcOffset = 14

  /// Byte offset of compressed size in local file header.
  internal static let localCompressedSizeOffset = 18

  /// Byte offset of uncompressed size in local file header.
  internal static let localUncompressedSizeOffset = 22

  /// Byte offset of file name length in local file header.
  internal static let localNameLengthOffset = 26

  /// Byte offset of extra field length in local file header.
  internal static let localExtraLengthOffset = 28

  /// Byte offset of the first local file header in an archive.
  internal static let firstEntryOffset = 0

  /// Most central-directory entries accepted in one archive.
  internal static let maximumEntryCount = 4_096

  /// Header size of one extra-field `(id, length)` record (APPNOTE 4.5.1).
  internal static let extraHeaderLength = 4

  /// Extra-field header ID for ZIP64 extended information (APPNOTE 4.5.3).
  internal static let extraZip64Id: UInt16 = 0x0001

  /// Extra-field header ID for Info-ZIP Unicode Comment (APPNOTE 4.6.8).
  internal static let extraUnicodeCommentId: UInt16 = 0x6375

  /// Extra-field header ID for Info-ZIP Unicode Path (APPNOTE 4.6.9).
  internal static let extraUnicodePathId: UInt16 = 0x7075

  /// Extra-field header ID for PKWARE Unix attributes / symlink targets (APPNOTE 4.5.7).
  internal static let extraPkwareUnixId: UInt16 = 0x000D

  /// Extra-field header ID for ASi Unix attributes / symlink targets.
  internal static let extraAsiUnixId: UInt16 = 0x756E

  /// Highest ASCII byte (`0x7F`), required when the UTF-8 filename flag (bit 11) is clear.
  internal static let maxAsciiByte: UInt8 = 0x7F

  /// Bit shift to the Unix file mode in external attributes (APPNOTE 4.4.15).
  internal static let unixModeShift = 16

  /// POSIX `S_IFMT` mask over the Unix file mode.
  internal static let unixFileTypeMask: UInt32 = 0o170_000

  /// POSIX `S_IFREG` regular-file mode bits.
  internal static let unixRegularFile: UInt32 = 0o100_000

  /// POSIX `S_IFDIR` directory mode bits.
  internal static let unixDirectory: UInt32 = 0o040_000

  /// MS-DOS directory attribute bit in external attributes (APPNOTE 4.4.15).
  internal static let dosDirectoryAttribute: UInt32 = 0x10

  /// Maximum ASCII C0 control scalar value (`0x1F`).
  internal static let maxAsciiControlScalar: UInt32 = 0x1F

  /// Start of ASCII DEL and C1 control scalars (`0x7F`).
  internal static let deleteControlScalar: UInt32 = 0x7F

  /// End of C1 control scalars (`0x9F`).
  internal static let maxC1ControlScalar: UInt32 = 0x9F

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
