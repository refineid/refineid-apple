// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Minimal ZIP reader for extracting ASiC-E and BDOC container contents.
///
/// Supports stored entries (ZIP compression method 0) and deflated entries
/// (ZIP compression method 8) decompressed via `FlateDecoder` with raw RFC 1951 framing.
///
/// Every entry name must be a plain relative UTF-8 path with no empty, `.`,
/// or `..` segments, no leading `/`, no `\`, and no control characters. An
/// archive with duplicate names (before or after case folding), local/central
/// header disagreement, unindexed local headers, or trailing bytes is refused.
internal enum ZipReader {
  /// One archive whose every entry was read and checked.
  internal struct Archive {
    /// All file entries, keyed by entry name.
    internal let entries: [String: Data]

    /// The file entry names in central-directory order.
    internal let names: [String]

    /// Explicit directory entry names in central-directory order.
    internal let directoryNames: [String]

    /// The name of the first central-directory entry, file or directory.
    internal let firstEntryName: String?

    /// The compression method of the first central-directory entry.
    internal let firstEntryMethod: UInt16?

    /// The general-purpose bit flags of the first central-directory entry.
    internal let firstEntryFlags: UInt16?

    /// The local-header offset of the first central-directory entry.
    internal let firstEntryLocalOffset: Int?

    /// The extra-field length in the first entry's local header.
    internal let firstEntryLocalExtraLength: Int?

    /// The extra-field length in the first entry's central-directory header.
    internal let firstEntryCentralExtraLength: Int?
  }

  /// Why an archive was refused.
  internal enum Failure: Error, Equatable {
    /// The unpacked bytes do not match the declared CRC-32.
    case crcMismatch

    /// Two entries share a name, or names equal after case folding.
    case duplicateName

    /// An entry name is empty, absolute, contains `\` or control characters, or uses `.` / `..`.
    case invalidEntryName

    /// The unpacked length differs from the declared size.
    case lengthMismatch

    /// The bytes do not form the ZIP structure the reader handles.
    case malformed

    /// The local header names a different entry than the central record.
    case nameMismatch

    /// A declared size, or the declared total, exceeds the ceiling.
    case sizeOverCeiling

    /// An entry uses a compression method other than stored or deflated.
    case unsupportedMethod
  }

  /// Header information for one central-directory entry.
  internal struct EntryHeader {
    internal let localOffset: Int
    internal let compressedSize: Int
    internal let uncompressedSize: Int
    internal let centralExtraLength: Int
    internal let flags: UInt16
    internal let method: UInt16
    internal let crc: UInt32
    internal let nameBytes: Data
    internal let name: String
    internal let normalizedKey: String
    internal let isDirectory: Bool
  }

  /// Byte range occupied by one local entry (header, data, and optional data descriptor).
  internal struct LocalExtent {
    internal let start: Int
    internal let end: Int
  }

  /// Parsed End of Central Directory geometry.
  internal struct EndOfDirectory {
    internal let eocdOffset: Int
    internal let entryCount: Int
    internal let directoryOffset: Int
  }

  /// Extracted local entry payload and layout facts.
  private struct ExtractedEntry {
    let data: Data
    let localExtraLength: Int
    let extent: LocalExtent
  }

  /// Whether the data begins with the standard ZIP local file header signature.
  internal static func hasZipSignature(_ data: Data) -> Bool {
    guard data.count >= ZipValues.localHeaderLength else { return false }
    return readUInt32(from: Data(data), at: 0) == ZipValues.localHeaderSignature
  }

  /// Reads and unpacks all entries from a complete ZIP byte buffer.
  ///
  /// Returns an empty dictionary when `open(_:)` refuses the archive.
  internal static func read(archive: Data) -> [String: Data] {
    (try? Self.open(archive))?.entries ?? [:]
  }

  /// Reads, unpacks and checks every entry of a complete ZIP byte buffer.
  internal static func open(_ data: Data) throws -> Archive {
    let archive = Data(data)
    let eocd = try Self.findEndOfCentralDirectory(in: archive)
    let headers = try Self.readCentralDirectory(from: archive, eocd: eocd)

    var entries: [String: Data] = [:]
    var names: [String] = []
    var directoryNames: [String] = []
    var extents: [LocalExtent] = []
    var firstLocalExtraLength: Int?
    for header in headers {
      let extracted = try Self.extractEntryData(from: archive, header: header)
      extents.append(extracted.extent)
      if firstLocalExtraLength == nil {
        firstLocalExtraLength = extracted.localExtraLength
      }
      if header.isDirectory {
        directoryNames.append(header.name)
      } else {
        entries[header.name] = extracted.data
        names.append(header.name)
      }
    }
    try Self.requireExactTiling(extents, directoryOffset: eocd.directoryOffset)
    return Archive(
      entries: entries,
      names: names,
      directoryNames: directoryNames,
      firstEntryName: headers.first?.name,
      firstEntryMethod: headers.first?.method,
      firstEntryFlags: headers.first?.flags,
      firstEntryLocalOffset: headers.first?.localOffset,
      firstEntryLocalExtraLength: firstLocalExtraLength,
      firstEntryCentralExtraLength: headers.first?.centralExtraLength
    )
  }

  /// Reads `eocd.entryCount` central-directory records and enforces uniqueness and size bounds.
  private static func readCentralDirectory(
    from archive: Data,
    eocd: EndOfDirectory
  ) throws -> [EntryHeader] {
    var headers: [EntryHeader] = []
    var seenFoldedNames: Set<String> = []
    var declaredTotal = 0
    var currentOffset = eocd.directoryOffset
    for _ in 0..<eocd.entryCount {
      let header = try Self.readCentralDirectoryEntry(from: archive, at: &currentOffset)
      guard seenFoldedNames.insert(header.normalizedKey).inserted else {
        throw Failure.duplicateName
      }
      let (nextTotal, overflow) = declaredTotal.addingReportingOverflow(header.uncompressedSize)
      guard !overflow, nextTotal <= ZipValues.maximumEntryByteCount else {
        throw Failure.sizeOverCeiling
      }
      declaredTotal = nextTotal
      headers.append(header)
    }
    guard currentOffset == eocd.eocdOffset else {
      throw Failure.malformed
    }
    return headers
  }

  /// Extracts and decompresses one entry from its local file header.
  private static func extractEntryData(
    from archive: Data,
    header: EntryHeader
  ) throws -> ExtractedEntry {
    let layout = try Self.verifiedLocalLayout(from: archive, header: header)
    if header.isDirectory {
      guard
        header.method == ZipValues.methodStored,
        header.compressedSize == 0,
        header.uncompressedSize == 0,
        header.crc == 0
      else {
        throw Failure.malformed
      }
      return ExtractedEntry(
        data: Data(),
        localExtraLength: layout.localExtraLength,
        extent: layout.extent
      )
    }

    let compressedBytes = archive.subdata(
      in: layout.dataStart..<(layout.dataStart + header.compressedSize))
    let uncompressedBytes = try Self.decompressPayload(compressedBytes, header: header)
    guard AsicContainer.ZipWriter.crc32(uncompressedBytes) == header.crc else {
      throw Failure.crcMismatch
    }
    return ExtractedEntry(
      data: uncompressedBytes,
      localExtraLength: layout.localExtraLength,
      extent: layout.extent
    )
  }

  /// Unpacks `compressedBytes` according to `header.method`.
  private static func decompressPayload(_ compressedBytes: Data, header: EntryHeader) throws -> Data
  {
    switch header.method {
    case ZipValues.methodStored:
      guard header.compressedSize == header.uncompressedSize else {
        throw Failure.lengthMismatch
      }
      return compressedBytes

    case ZipValues.methodDeflated:
      switch FlateDecoder.inflateRawExact(compressedBytes, expectedCount: header.uncompressedSize) {
      case .decoded(let bytes):
        return bytes

      case .lengthMismatch:
        throw Failure.lengthMismatch

      case .malformed:
        throw Failure.malformed
      }

    default:
      throw Failure.unsupportedMethod
    }
  }

  internal static func readUInt16(from data: Data, at offset: Int) -> UInt16 {
    let start = data.startIndex + offset
    let bytes = data[start..<(start + MemoryLayout<UInt16>.size)]
    return bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self).littleEndian }
  }

  internal static func readUInt32(from data: Data, at offset: Int) -> UInt32 {
    let start = data.startIndex + offset
    let bytes = data[start..<(start + MemoryLayout<UInt32>.size)]
    return bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
  }
}
