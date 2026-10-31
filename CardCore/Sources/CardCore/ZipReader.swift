// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import zlib

/// Minimal ZIP reader for extracting ASiC-E container contents.
///
/// Supports stored entries (ZIP compression method 0) and deflated entries
/// (ZIP compression method 8) decompressed via zlib with raw RFC 1951 framing.
///
/// A name resolves to exactly one entry (EN 319 162-1 clause 5.2): an
/// archive with two entries of one name, or of names equal after case
/// folding, is refused, and so is one whose local header names its entry
/// differently from the central directory.
internal enum ZipReader {
  /// One archive whose every entry was read and checked.
  internal struct Archive {
    /// All entries, keyed by entry name.
    internal let entries: [String: Data]

    /// The entry names in central-directory order.
    internal let names: [String]

    /// The compression method of the first central-directory entry.
    internal let firstEntryMethod: UInt16?

    /// The local-header offset of the first central-directory entry.
    internal let firstEntryLocalOffset: Int?

    /// The extra-field length in the first entry's local header.
    internal let firstEntryLocalExtraLength: Int?
  }

  /// Why an archive was refused.
  internal enum Failure: Error, Equatable {
    /// The unpacked bytes do not match the declared CRC-32.
    case crcMismatch

    /// Two entries share a name, or names equal after case folding.
    case duplicateName

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

  /// Header information for one central directory file entry.
  private struct EntryHeader {
    let localOffset: Int
    let compressedSize: Int
    let uncompressedSize: Int
    let method: UInt16
    let crc: UInt32
    let nameBytes: Data
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
    guard let eocdOffset = findEndOfCentralDirectory(in: archive),
      eocdOffset + ZipValues.eocdRecordLength <= archive.count
    else {
      throw Failure.malformed
    }
    let entryCount = Int(
      readUInt16(from: archive, at: eocdOffset + ZipValues.eocdEntryCountOffset))
    let directorySize = Int(
      readUInt32(from: archive, at: eocdOffset + ZipValues.eocdDirectorySizeOffset))
    let directoryOffset = Int(
      readUInt32(from: archive, at: eocdOffset + ZipValues.eocdDirectoryOffsetOffset))
    _ = try Self.end(of: directoryOffset, spanning: [directorySize], within: archive)

    var headers: [(name: String, header: EntryHeader)] = []
    var seenNames: Set<String> = []
    var seenFoldedNames: Set<String> = []
    var declaredTotal = 0
    var currentOffset = directoryOffset
    for _ in 0..<entryCount {
      let read = try readCentralDirectoryEntry(from: archive, at: &currentOffset)
      guard
        seenNames.insert(read.name).inserted,
        seenFoldedNames.insert(read.name.lowercased()).inserted
      else {
        throw Failure.duplicateName
      }
      declaredTotal += read.header.uncompressedSize
      guard declaredTotal <= ZipValues.maximumEntryByteCount else {
        throw Failure.sizeOverCeiling
      }
      headers.append(read)
    }

    var entries: [String: Data] = [:]
    var firstLocalExtraLength: Int?
    for (name, header) in headers {
      let extracted = try extractEntryData(from: archive, header: header)
      entries[name] = extracted.data
      if firstLocalExtraLength == nil { firstLocalExtraLength = extracted.localExtraLength }
    }
    return Archive(
      entries: entries,
      names: headers.map(\.name),
      firstEntryMethod: headers.first?.header.method,
      firstEntryLocalOffset: headers.first?.header.localOffset,
      firstEntryLocalExtraLength: firstLocalExtraLength
    )
  }

  private static func readCentralDirectoryEntry(
    from archive: Data,
    at offset: inout Int
  ) throws -> (name: String, header: EntryHeader) {
    _ = try Self.end(
      of: offset, spanning: [ZipValues.centralDirectoryHeaderLength], within: archive)
    guard readUInt32(from: archive, at: offset) == ZipValues.centralHeaderSignature else {
      throw Failure.malformed
    }

    let compressedSize = Int(
      readUInt32(from: archive, at: offset + ZipValues.cdCompressedSizeOffset))
    let uncompressedSize = Int(
      readUInt32(from: archive, at: offset + ZipValues.cdUncompressedSizeOffset))
    guard
      compressedSize <= ZipValues.maximumEntryByteCount,
      uncompressedSize <= ZipValues.maximumEntryByteCount
    else {
      throw Failure.sizeOverCeiling
    }

    let nameLength = Int(readUInt16(from: archive, at: offset + ZipValues.cdNameLengthOffset))
    let extraLength = Int(readUInt16(from: archive, at: offset + ZipValues.cdExtraLengthOffset))
    let commentLength = Int(readUInt16(from: archive, at: offset + ZipValues.cdCommentLengthOffset))

    let nameStart = offset + ZipValues.centralDirectoryHeaderLength
    let nextOffset = try Self.end(
      of: nameStart, spanning: [nameLength, extraLength, commentLength], within: archive)
    let nameBytes = archive.subdata(in: nameStart..<(nameStart + nameLength))
    guard
      let name = String(data: nameBytes, encoding: .utf8)
        ?? String(data: nameBytes, encoding: .ascii)
    else {
      throw Failure.malformed
    }

    let header = EntryHeader(
      localOffset: Int(readUInt32(from: archive, at: offset + ZipValues.cdLocalHeaderOffset)),
      compressedSize: compressedSize,
      uncompressedSize: uncompressedSize,
      method: readUInt16(from: archive, at: offset + ZipValues.cdMethodOffset),
      crc: readUInt32(from: archive, at: offset + ZipValues.cdCrcOffset),
      nameBytes: nameBytes
    )
    offset = nextOffset
    return (name, header)
  }

  /// Locates the End of Central Directory record by scanning backwards from the end.
  private static func findEndOfCentralDirectory(in data: Data) -> Int? {
    guard data.count >= ZipValues.eocdRecordLength else { return nil }
    let minSearch = max(0, data.count - ZipValues.eocdSearchLimit)
    var offset = data.count - ZipValues.eocdRecordLength
    while offset >= minSearch {
      if readUInt32(from: data, at: offset) == ZipValues.endOfDirectorySignature {
        return offset
      }
      offset -= 1
    }
    return nil
  }

  /// Extracts and decompresses one entry from its local file header.
  private static func extractEntryData(
    from archive: Data,
    header: EntryHeader
  ) throws -> (data: Data, localExtraLength: Int) {
    _ = try Self.end(
      of: header.localOffset, spanning: [ZipValues.localHeaderLength], within: archive)
    guard readUInt32(from: archive, at: header.localOffset) == ZipValues.localHeaderSignature
    else {
      throw Failure.malformed
    }

    let localNameLength = Int(
      readUInt16(from: archive, at: header.localOffset + ZipValues.localNameLengthOffset))
    let localExtraLength = Int(
      readUInt16(from: archive, at: header.localOffset + ZipValues.localExtraLengthOffset))
    let localNameStart = header.localOffset + ZipValues.localHeaderLength
    _ = try Self.end(of: localNameStart, spanning: [localNameLength], within: archive)
    guard
      archive.subdata(in: localNameStart..<(localNameStart + localNameLength))
        == header.nameBytes
    else {
      throw Failure.nameMismatch
    }
    let dataStart = try Self.end(
      of: localNameStart, spanning: [localNameLength, localExtraLength], within: archive)
    _ = try Self.end(of: dataStart, spanning: [header.compressedSize], within: archive)

    let compressedBytes = archive.subdata(in: dataStart..<(dataStart + header.compressedSize))
    let uncompressedBytes: Data
    switch header.method {
    case ZipValues.methodStored:
      guard header.compressedSize == header.uncompressedSize else {
        throw Failure.lengthMismatch
      }
      uncompressedBytes = compressedBytes

    case ZipValues.methodDeflated:
      uncompressedBytes = try decompressDeflate(
        compressedBytes, uncompressedSize: header.uncompressedSize)

    default:
      throw Failure.unsupportedMethod
    }

    guard AsicContainer.ZipWriter.crc32(uncompressedBytes) == header.crc else {
      throw Failure.crcMismatch
    }
    return (uncompressedBytes, localExtraLength)
  }

  /// The offset after `start` and every length in `lengths`, refused as
  /// malformed when the sum overflows or passes the end of `archive`.
  private static func end(
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

  /// Decompresses raw DEFLATE bytes (RFC 1951) into exactly
  /// `uncompressedSize` bytes.
  ///
  /// The stream must end, consume every compressed byte, and produce
  /// exactly the declared length; a stream that would produce more is
  /// refused when the declared buffer is full.
  private static func decompressDeflate(
    _ compressed: Data,
    uncompressedSize: Int
  ) throws -> Data {
    var stream = z_stream()
    let initStatus = inflateInit2_(
      &stream,
      ZipValues.zlibRawDeflateWindowBits,
      ZLIB_VERSION,
      Int32(MemoryLayout<z_stream>.size)
    )
    guard initStatus == Z_OK else { throw Failure.malformed }
    defer { inflateEnd(&stream) }

    // One spare byte lets an over-long stream show itself.
    var result = Data(count: uncompressedSize + 1)
    var source = compressed
    let produced: Int? = result.withUnsafeMutableBytes { destBuffer in
      source.withUnsafeMutableBytes { srcBuffer in
        guard let destBase = destBuffer.baseAddress else { return nil }
        stream.next_in = srcBuffer.baseAddress?.assumingMemoryBound(to: Bytef.self)
        stream.avail_in = uInt(srcBuffer.count)
        stream.next_out = destBase.assumingMemoryBound(to: Bytef.self)
        stream.avail_out = uInt(destBuffer.count)
        let status = inflate(&stream, Z_FINISH)
        if status == Z_STREAM_END, stream.avail_in == 0 {
          return destBuffer.count - Int(stream.avail_out)
        }
        // Output past the declared size fills the spare byte.
        return stream.avail_out == 0 ? destBuffer.count : nil
      }
    }
    guard let produced else { throw Failure.malformed }
    guard produced == uncompressedSize else { throw Failure.lengthMismatch }
    return Data(result.prefix(uncompressedSize))
  }

  private static func readUInt16(from data: Data, at offset: Int) -> UInt16 {
    let start = data.startIndex + offset
    let bytes = data[start..<(start + MemoryLayout<UInt16>.size)]
    return bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self).littleEndian }
  }

  private static func readUInt32(from data: Data, at offset: Int) -> UInt32 {
    let start = data.startIndex + offset
    let bytes = data[start..<(start + MemoryLayout<UInt32>.size)]
    return bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
  }
}
