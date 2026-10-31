// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import zlib

@testable import CardCore

/// A ZIP archive assembled field by field, so a test can make the
/// local header, the central record and the data disagree.
internal struct SyntheticZipArchive {
  /// The fixture could not be built.
  internal enum Failure: Error {
    case deflate
  }

  /// One entry as written.
  internal struct Entry {
    /// The name in the central record.
    internal var name: String

    /// The name in the local header.
    internal var localName: String

    /// The bytes stored after the local header.
    internal var payload: Data

    /// The compression method in both headers.
    internal var method: UInt16

    /// The declared compressed size.
    internal var compressedSize: UInt32

    /// The declared uncompressed size.
    internal var uncompressedSize: UInt32

    /// The declared CRC-32.
    internal var crc: UInt32

    /// The local header's extra field.
    internal var localExtra = Data()

    /// The comment length the central record declares, with no
    /// comment bytes written.
    internal var declaredCommentLength = UInt16.zero

    /// A stored entry whose headers describe `content` truthfully.
    internal static func stored(_ name: String, _ content: Data) -> Self {
      let size = UInt32(content.count)
      return Self(
        name: name,
        localName: name,
        payload: content,
        method: ZipValues.methodStored,
        compressedSize: size,
        uncompressedSize: size,
        crc: AsicContainer.ZipWriter.crc32(content)
      )
    }

    /// A deflated entry whose headers describe `content` truthfully.
    internal static func deflated(_ name: String, _ content: Data) throws -> Self {
      let compressed = try SyntheticZipArchive.rawDeflate(content)
      return Self(
        name: name,
        localName: name,
        payload: compressed,
        method: ZipValues.methodDeflated,
        compressedSize: UInt32(compressed.count),
        uncompressedSize: UInt32(content.count),
        crc: AsicContainer.ZipWriter.crc32(content)
      )
    }
  }

  /// zlib's default memory level for the compressor state.
  private static let memoryLevel: Int32 = 8

  /// The entries, in archive order.
  internal var entries: [Entry]

  /// The archive bytes: local headers and data, the central directory,
  /// then its end record.
  internal var encoded: Data {
    let none = UInt16.zero
    var out = Data()
    var directory = Data()
    for entry in entries {
      let offset = UInt32(out.count)
      let localName = Data(entry.localName.utf8)
      let centralName = Data(entry.name.utf8)
      out.append(Self.field(ZipValues.localHeaderSignature))
      out.append(Self.field(ZipValues.versionNeeded))
      out.append(Self.field(none))
      out.append(Self.field(entry.method))
      out.append(Self.field(none))
      out.append(Self.field(none))
      out.append(Self.field(entry.crc))
      out.append(Self.field(entry.compressedSize))
      out.append(Self.field(entry.uncompressedSize))
      out.append(Self.field(UInt16(localName.count)))
      out.append(Self.field(UInt16(entry.localExtra.count)))
      out.append(localName)
      out.append(entry.localExtra)
      out.append(entry.payload)

      directory.append(Self.field(ZipValues.centralHeaderSignature))
      directory.append(Self.field(ZipValues.versionMadeBy))
      directory.append(Self.field(ZipValues.versionNeeded))
      directory.append(Self.field(none))
      directory.append(Self.field(entry.method))
      directory.append(Self.field(none))
      directory.append(Self.field(none))
      directory.append(Self.field(entry.crc))
      directory.append(Self.field(entry.compressedSize))
      directory.append(Self.field(entry.uncompressedSize))
      directory.append(Self.field(UInt16(centralName.count)))
      directory.append(Self.field(none))
      directory.append(Self.field(entry.declaredCommentLength))
      directory.append(Self.field(none))
      directory.append(Self.field(none))
      directory.append(Self.field(ZipValues.regularFileExternalAttributes))
      directory.append(Self.field(offset))
      directory.append(centralName)
    }
    let directoryAt = UInt32(out.count)
    out.append(directory)
    out.append(Self.field(ZipValues.endOfDirectorySignature))
    out.append(Self.field(none))
    out.append(Self.field(none))
    out.append(Self.field(UInt16(entries.count)))
    out.append(Self.field(UInt16(entries.count)))
    out.append(Self.field(UInt32(directory.count)))
    out.append(Self.field(directoryAt))
    out.append(Self.field(none))
    return out
  }

  /// One little-endian field.
  private static func field(_ value: UInt16) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
  }

  /// One little-endian field.
  private static func field(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
  }

  /// `content` as raw DEFLATE (RFC 1951), the framing ZIP method 8 uses.
  fileprivate static func rawDeflate(_ content: Data) throws -> Data {
    var stream = z_stream()
    guard
      deflateInit2_(
        &stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, ZipValues.zlibRawDeflateWindowBits,
        Self.memoryLevel, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)
      ) == Z_OK
    else {
      throw Failure.deflate
    }
    defer { deflateEnd(&stream) }
    var source = content
    var output = Data(count: Int(deflateBound(&stream, uLong(content.count))))
    let produced: Int? = output.withUnsafeMutableBytes { destination in
      source.withUnsafeMutableBytes { input in
        stream.next_in = input.baseAddress?.assumingMemoryBound(to: Bytef.self)
        stream.avail_in = uInt(input.count)
        stream.next_out = destination.baseAddress?.assumingMemoryBound(to: Bytef.self)
        stream.avail_out = uInt(destination.count)
        guard deflate(&stream, Z_FINISH) == Z_STREAM_END else { return nil }
        return destination.count - Int(stream.avail_out)
      }
    }
    guard let produced else { throw Failure.deflate }
    return Data(output.prefix(produced))
  }
}
