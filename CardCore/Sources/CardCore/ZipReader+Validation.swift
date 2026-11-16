// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Structural, path-segment, and byte-tiling validation for `ZipReader`.
extension ZipReader {
  /// Validated local header offsets and extent for one entry.
  internal struct LocalLayout {
    internal let dataStart: Int
    internal let localExtraLength: Int
    internal let extent: LocalExtent
  }

  /// Path-segment characters and components forbidden in ZIP entry names.
  private enum PathToken {
    static let separator: Character = "/"
    static let backslash: Character = "\\"
    static let current = "."
    static let parent = ".."
  }

  /// Entry kind stated by central-directory external file attributes.
  private enum ExternalEntryKind {
    case unspecified
    case regularFile
    case directory
  }

  /// Validated size, offset, and flag fields from one central-directory record.
  private struct CentralHeaderFields {
    let localOffset: Int
    let compressedSize: Int
    let uncompressedSize: Int
    let flags: UInt16
  }

  /// Validated entry name and its case-folded uniqueness key.
  private struct ValidatedEntryName {
    let name: String
    let normalizedKey: String
    let isDirectory: Bool
  }

  /// Locates the End of Central Directory record ending at `archive.count` and validates geometry.
  internal static func findEndOfCentralDirectory(in archive: Data) throws -> EndOfDirectory {
    guard archive.count >= ZipValues.eocdRecordLength else { throw Failure.malformed }
    let minSearch = max(0, archive.count - ZipValues.eocdSearchLimit)
    var offset = archive.count - ZipValues.eocdRecordLength
    while offset >= minSearch {
      if readUInt32(from: archive, at: offset) == ZipValues.endOfDirectorySignature {
        let commentLength = Int(
          readUInt16(from: archive, at: offset + ZipValues.eocdCommentLengthOffset))
        if offset + ZipValues.eocdRecordLength + commentLength == archive.count {
          return try Self.validatedEndOfDirectory(in: archive, at: offset)
        }
      }
      offset -= 1
    }
    throw Failure.malformed
  }

  /// Reads one central-directory record and advances `offset`.
  internal static func readCentralDirectoryEntry(
    from archive: Data,
    at offset: inout Int
  ) throws -> EntryHeader {
    let fields = try Self.validatedCentralFields(in: archive, at: offset)
    let externalAttributes = readUInt32(
      from: archive, at: offset + ZipValues.cdExternalAttributesOffset)
    let externalKind = try Self.externalEntryKind(externalAttributes)
    let nameLength = Int(readUInt16(from: archive, at: offset + ZipValues.cdNameLengthOffset))
    let extraLength = Int(readUInt16(from: archive, at: offset + ZipValues.cdExtraLengthOffset))
    let commentLength = Int(readUInt16(from: archive, at: offset + ZipValues.cdCommentLengthOffset))

    let nameStart = offset + ZipValues.centralDirectoryHeaderLength
    let extraStart = try Self.end(of: nameStart, spanning: [nameLength], within: archive)
    let commentStart = try Self.end(of: extraStart, spanning: [extraLength], within: archive)
    let nextOffset = try Self.end(of: commentStart, spanning: [commentLength], within: archive)
    try Self.requirePlainExtraField(archive.subdata(in: extraStart..<commentStart))

    let nameBytes = archive.subdata(in: nameStart..<extraStart)
    let parsedName = try Self.validatedEntryName(
      nameBytes, flags: fields.flags, externalKind: externalKind)

    let header = EntryHeader(
      localOffset: fields.localOffset,
      compressedSize: fields.compressedSize,
      uncompressedSize: fields.uncompressedSize,
      centralExtraLength: extraLength,
      flags: fields.flags,
      method: readUInt16(from: archive, at: offset + ZipValues.cdMethodOffset),
      crc: readUInt32(from: archive, at: offset + ZipValues.cdCrcOffset),
      nameBytes: nameBytes,
      name: parsedName.name,
      normalizedKey: parsedName.normalizedKey,
      isDirectory: parsedName.isDirectory
    )
    offset = nextOffset
    return header
  }

  private static func validatedCentralFields(
    in archive: Data,
    at offset: Int
  ) throws -> CentralHeaderFields {
    _ = try Self.end(
      of: offset, spanning: [ZipValues.centralDirectoryHeaderLength], within: archive)
    guard readUInt32(from: archive, at: offset) == ZipValues.centralHeaderSignature else {
      throw Failure.malformed
    }
    let rawCompSize = readUInt32(from: archive, at: offset + ZipValues.cdCompressedSizeOffset)
    let rawUncompSize = readUInt32(from: archive, at: offset + ZipValues.cdUncompressedSizeOffset)
    let rawLocalOffset = readUInt32(from: archive, at: offset + ZipValues.cdLocalHeaderOffset)
    let diskNumber = readUInt16(from: archive, at: offset + ZipValues.cdDiskNumberOffset)
    let flags = readUInt16(from: archive, at: offset + ZipValues.cdFlagsOffset)
    guard
      rawCompSize != UInt32.max,
      rawUncompSize != UInt32.max,
      rawLocalOffset != UInt32.max,
      diskNumber == 0,
      flags & ZipValues.encryptedFlagsMask == 0
    else {
      throw Failure.malformed
    }
    let compressedSize = Int(rawCompSize)
    let uncompressedSize = Int(rawUncompSize)
    guard
      compressedSize <= ZipValues.maximumEntryByteCount,
      uncompressedSize <= ZipValues.maximumEntryByteCount
    else {
      throw Failure.sizeOverCeiling
    }
    return CentralHeaderFields(
      localOffset: Int(rawLocalOffset),
      compressedSize: compressedSize,
      uncompressedSize: uncompressedSize,
      flags: flags
    )
  }

  /// Checks the local header and optional data descriptor against `header`.
  internal static func verifiedLocalLayout(
    from archive: Data,
    header: EntryHeader
  ) throws -> LocalLayout {
    let base = header.localOffset
    _ = try Self.end(of: base, spanning: [ZipValues.localHeaderLength], within: archive)
    guard readUInt32(from: archive, at: base) == ZipValues.localHeaderSignature else {
      throw Failure.malformed
    }

    let localNameLength = Int(readUInt16(from: archive, at: base + ZipValues.localNameLengthOffset))
    let localExtraLength = Int(
      readUInt16(from: archive, at: base + ZipValues.localExtraLengthOffset))
    let localNameStart = base + ZipValues.localHeaderLength
    let localExtraStart = try Self.end(
      of: localNameStart, spanning: [localNameLength], within: archive)
    guard archive.subdata(in: localNameStart..<localExtraStart) == header.nameBytes else {
      throw Failure.nameMismatch
    }

    let dataStart = try Self.end(of: localExtraStart, spanning: [localExtraLength], within: archive)
    let dataEnd = try Self.end(of: dataStart, spanning: [header.compressedSize], within: archive)
    try Self.requireLocalFieldsAgree(in: archive, at: base, header: header)
    try Self.requirePlainExtraField(archive.subdata(in: localExtraStart..<dataStart))

    let recordEnd: Int
    if header.flags & ZipValues.dataDescriptorFlag != 0 {
      recordEnd = try Self.readDataDescriptor(in: archive, at: dataEnd, header: header)
    } else {
      recordEnd = dataEnd
    }
    return LocalLayout(
      dataStart: dataStart,
      localExtraLength: localExtraLength,
      extent: LocalExtent(start: base, end: recordEnd)
    )
  }

  /// Ensures local entries tile `0..<directoryOffset` byte for byte with no gaps or overlaps.
  internal static func requireExactTiling(
    _ extents: [LocalExtent],
    directoryOffset: Int
  ) throws {
    let sorted = extents.sorted { lhs, rhs in lhs.start < rhs.start }
    var cursor = ZipValues.firstEntryOffset
    for extent in sorted {
      guard extent.start == cursor, extent.end >= extent.start else {
        throw Failure.malformed
      }
      cursor = extent.end
    }
    guard cursor == directoryOffset else {
      throw Failure.malformed
    }
  }

  private static func validatedEndOfDirectory(
    in archive: Data,
    at offset: Int
  ) throws -> EndOfDirectory {
    let diskNumber = readUInt16(from: archive, at: offset + ZipValues.eocdDiskNumberOffset)
    let directoryDisk = readUInt16(from: archive, at: offset + ZipValues.eocdDirectoryDiskOffset)
    let diskCount = readUInt16(from: archive, at: offset + ZipValues.eocdDiskEntryCountOffset)
    let entryCount = readUInt16(from: archive, at: offset + ZipValues.eocdEntryCountOffset)
    let rawDirSize = readUInt32(from: archive, at: offset + ZipValues.eocdDirectorySizeOffset)
    let rawDirOffset = readUInt32(from: archive, at: offset + ZipValues.eocdDirectoryOffsetOffset)
    let hasZip64Locator =
      offset >= ZipValues.zip64LocatorLength
      && readUInt32(from: archive, at: offset - ZipValues.zip64LocatorLength)
        == ZipValues.zip64LocatorSignature
    guard
      !hasZip64Locator,
      diskNumber == 0,
      directoryDisk == 0,
      diskCount == entryCount,
      entryCount != UInt16.max,
      Int(entryCount) <= ZipValues.maximumEntryCount,
      rawDirSize != UInt32.max,
      rawDirOffset != UInt32.max
    else {
      throw Failure.malformed
    }
    let directoryOffset = Int(rawDirOffset)
    let directoryEnd = try Self.end(
      of: directoryOffset, spanning: [Int(rawDirSize)], within: archive)
    guard directoryEnd == offset else { throw Failure.malformed }
    return EndOfDirectory(
      eocdOffset: offset,
      entryCount: Int(entryCount),
      directoryOffset: directoryOffset
    )
  }

  private static func validatedEntryName(
    _ nameBytes: Data,
    flags: UInt16,
    externalKind: ExternalEntryKind
  ) throws -> ValidatedEntryName {
    if flags & ZipValues.utf8NameFlag == 0 {
      guard nameBytes.allSatisfy({ $0 <= ZipValues.maxAsciiByte }) else {
        throw Failure.malformed
      }
    }
    guard let name = String(data: nameBytes, encoding: .utf8) else {
      throw Failure.malformed
    }
    guard
      !name.isEmpty,
      !name.hasPrefix(String(PathToken.separator)),
      !name.contains(PathToken.backslash),
      !name.unicodeScalars.contains(where: Self.isControlScalar)
    else {
      throw Failure.invalidEntryName
    }
    let isDirectory = name.hasSuffix(String(PathToken.separator))
    if (externalKind == .directory && !isDirectory)
      || (externalKind == .regularFile && isDirectory)
    {
      throw Failure.malformed
    }
    let trimmed = isDirectory ? String(name.dropLast()) : name
    let segments = trimmed.split(separator: PathToken.separator, omittingEmptySubsequences: false)
    guard
      !segments.isEmpty,
      segments.allSatisfy({ segment in
        !segment.isEmpty && segment != PathToken.current && segment != PathToken.parent
      })
    else {
      throw Failure.invalidEntryName
    }
    return ValidatedEntryName(
      name: name,
      normalizedKey: trimmed.lowercased(),
      isDirectory: isDirectory
    )
  }

  private static func isControlScalar(_ scalar: Unicode.Scalar) -> Bool {
    scalar.value <= ZipValues.maxAsciiControlScalar
      || (scalar.value >= ZipValues.deleteControlScalar
        && scalar.value <= ZipValues.maxC1ControlScalar)
  }

  private static func externalEntryKind(_ external: UInt32) throws -> ExternalEntryKind {
    let unixType = (external >> ZipValues.unixModeShift) & ZipValues.unixFileTypeMask
    let hasDosDirectory = external & ZipValues.dosDirectoryAttribute != 0
    switch unixType {
    case 0:
      return hasDosDirectory ? .directory : .unspecified

    case ZipValues.unixRegularFile:
      guard !hasDosDirectory else { throw Failure.malformed }
      return .regularFile

    case ZipValues.unixDirectory:
      return .directory

    default:
      throw Failure.malformed
    }
  }

  private static func requirePlainExtraField(_ extra: Data) throws {
    let forbiddenIds: Set<UInt16> = [
      ZipValues.extraZip64Id, ZipValues.extraUnicodePathId, ZipValues.extraUnicodeCommentId,
      ZipValues.extraPkwareUnixId, ZipValues.extraAsiUnixId,
    ]
    var cursor = 0
    while cursor < extra.count {
      let bodyStart = try Self.end(
        of: cursor, spanning: [ZipValues.extraHeaderLength], within: extra)
      let headerId = readUInt16(from: extra, at: cursor)
      let dataSize = Int(readUInt16(from: extra, at: cursor + MemoryLayout<UInt16>.size))
      cursor = try Self.end(of: bodyStart, spanning: [dataSize], within: extra)
      guard !forbiddenIds.contains(headerId) else { throw Failure.malformed }
    }
  }

  private static func requireLocalFieldsAgree(
    in archive: Data,
    at base: Int,
    header: EntryHeader
  ) throws {
    let localFlags = readUInt16(from: archive, at: base + ZipValues.localFlagsOffset)
    let localMethod = readUInt16(from: archive, at: base + ZipValues.localMethodOffset)
    let localCrc = readUInt32(from: archive, at: base + ZipValues.localCrcOffset)
    let localComp = Int(readUInt32(from: archive, at: base + ZipValues.localCompressedSizeOffset))
    let localUncomp = Int(
      readUInt32(from: archive, at: base + ZipValues.localUncompressedSizeOffset))
    let hasDescriptor = localFlags & ZipValues.dataDescriptorFlag != 0
    let sizesAgree: Bool
    if hasDescriptor {
      sizesAgree =
        (localCrc == 0 || localCrc == header.crc)
        && (localComp == 0 || localComp == header.compressedSize)
        && (localUncomp == 0 || localUncomp == header.uncompressedSize)
    } else {
      sizesAgree =
        localCrc == header.crc
        && localComp == header.compressedSize
        && localUncomp == header.uncompressedSize
    }
    guard
      localFlags == header.flags,
      localMethod == header.method,
      sizesAgree
    else {
      throw Failure.malformed
    }
  }

  private static func readDataDescriptor(
    in archive: Data,
    at offset: Int,
    header: EntryHeader
  ) throws -> Int {
    _ = try Self.end(of: offset, spanning: [ZipValues.dataDescriptorLength], within: archive)
    let firstWord = readUInt32(from: archive, at: offset)
    let fieldsStart: Int
    let descriptorEnd: Int
    if firstWord == ZipValues.dataDescriptorSignature {
      descriptorEnd = try Self.end(
        of: offset, spanning: [ZipValues.signedDataDescriptorLength], within: archive)
      fieldsStart = offset + MemoryLayout<UInt32>.size
    } else {
      descriptorEnd = offset + ZipValues.dataDescriptorLength
      fieldsStart = offset
    }
    let crc = readUInt32(from: archive, at: fieldsStart)
    let comp = Int(readUInt32(from: archive, at: fieldsStart + MemoryLayout<UInt32>.size))
    let uncomp = Int(
      readUInt32(
        from: archive, at: fieldsStart + MemoryLayout<UInt32>.size + MemoryLayout<UInt32>.size))
    guard crc == header.crc, comp == header.compressedSize, uncomp == header.uncompressedSize else {
      throw Failure.malformed
    }
    return descriptorEnd
  }

  /// The offset after `start` and every length in `lengths`, refused as
  /// malformed when the sum overflows or passes the end of `archive`.
  internal static func end(
    of start: Int,
    spanning lengths: [Int],
    within archive: Data
  ) throws -> Int {
    var end = start
    for length in lengths {
      let (sum, overflow) = end.addingReportingOverflow(length)
      guard !overflow, length >= 0 else { throw Failure.malformed }
      end = sum
    }
    guard start >= 0, end <= archive.count else { throw Failure.malformed }
    return end
  }
}
