// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import zlib

/// The minimal ZIP writer the container is assembled with.
extension AsicContainer {
  /// A ZIP writer of stored entries only.
  ///
  /// This target carries no archive framework and the container needs
  /// one method of one compression mode. Stored entries also mean the
  /// archive can be read with nothing but an offset table, which is
  /// the property ASiC leans on for the mimetype entry.
  internal struct ZipWriter {
    /// Bytes written so far: local headers and entry data.
    private var out = Data()

    /// Central-directory records, emitted at the end.
    private var directory = Data()

    /// Number of entries added.
    private var count: UInt16 = 0

    /// Set when an entry could not be described by the 32-bit fields.
    ///
    /// Sticky: once true the archive is unusable, so `finish` refuses
    /// rather than returning something that looks like a container.
    private var overflowed = false

    /// One little-endian field of the ZIP structure.
    private static func field(_ value: UInt16) -> Data {
      withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    /// One little-endian field of the ZIP structure.
    private static func field(_ value: UInt32) -> Data {
      withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    /// CRC-32 as ZIP defines it (IEEE 802.3 polynomial, reflected).
    internal static func crc32(_ data: Data) -> UInt32 {
      data.withUnsafeBytes { raw in
        guard let base = raw.bindMemory(to: Bytef.self).baseAddress else {
          return UInt32(zlib.crc32(0, nil, 0))
        }
        var crc = zlib.crc32(0, nil, 0)
        var offset = 0
        while offset < raw.count {
          let chunk = min(raw.count - offset, Int(uInt.max))
          crc = zlib.crc32(crc, base.advanced(by: offset), uInt(chunk))
          offset += chunk
        }
        return UInt32(crc)
      }
    }

    /// Appends one stored entry.
    ///
    /// Failure means the entry cannot be described by the 32-bit ZIP
    /// fields. Clamping instead would write a length that does not
    /// match the data and call it a success.
    internal mutating func add(name: String, content: Data) {
      let nameBytes = Data(name.utf8)
      guard
        let offset = UInt32(exactly: out.count),
        let size = UInt32(exactly: content.count),
        let nameLength = UInt16(exactly: nameBytes.count),
        count != UInt16.max
      else {
        overflowed = true
        return
      }
      let crc = Self.crc32(content)
      // Bit 11 declares the name UTF-8. Without it a reader falls back
      // to CP437 and a name with accents comes out as mojibake - a
      // data object whose name no longer matches the one the signature
      // covers. No other flag: no encryption, no data descriptor.
      let flags = name.allSatisfy(\.isASCII) ? 0 : ZipValues.utf8NameFlag

      out.append(Self.field(ZipValues.localHeaderSignature))
      out.append(Self.field(ZipValues.versionNeeded))
      out.append(Self.field(flags))
      out.append(Self.field(ZipValues.methodStored))
      // Zero timestamps rather than a clock read: a container that is
      // byte-identical for identical inputs is worth more than a
      // modification time nobody consults.
      out.append(Self.field(UInt16(0)))
      out.append(Self.field(UInt16(0)))
      out.append(Self.field(crc))
      out.append(Self.field(size))
      out.append(Self.field(size))
      out.append(Self.field(nameLength))
      out.append(Self.field(UInt16(0)))
      out.append(nameBytes)
      out.append(content)

      directory.append(Self.field(ZipValues.centralHeaderSignature))
      // Version made by, then version needed.
      directory.append(Self.field(ZipValues.versionMadeBy))
      directory.append(Self.field(ZipValues.versionNeeded))
      directory.append(Self.field(flags))
      directory.append(Self.field(ZipValues.methodStored))
      directory.append(Self.field(UInt16(0)))
      directory.append(Self.field(UInt16(0)))
      directory.append(Self.field(crc))
      directory.append(Self.field(size))
      directory.append(Self.field(size))
      directory.append(Self.field(nameLength))
      // Extra field, comment, disk number, internal attributes.
      directory.append(Self.field(UInt16(0)))
      directory.append(Self.field(UInt16(0)))
      directory.append(Self.field(UInt16(0)))
      directory.append(Self.field(UInt16(0)))
      // External attributes.
      directory.append(Self.field(ZipValues.regularFileExternalAttributes))
      directory.append(Self.field(offset))
      directory.append(nameBytes)

      count += 1
    }

    /// Closes the archive: central directory, then its locator.
    ///
    /// Nil when anything overflowed the 32-bit fields.
    internal consuming func finish() -> Data? {
      guard !overflowed,
        let directoryAt = UInt32(exactly: out.count),
        let directorySize = UInt32(exactly: directory.count)
      else {
        return nil
      }
      out.append(directory)
      out.append(Self.field(ZipValues.endOfDirectorySignature))
      // Disk numbers: single-volume, as ISO/IEC 21320-1 requires.
      out.append(Self.field(UInt16(0)))
      out.append(Self.field(UInt16(0)))
      out.append(Self.field(count))
      out.append(Self.field(count))
      out.append(Self.field(directorySize))
      out.append(Self.field(directoryAt))
      out.append(Self.field(UInt16(0)))
      return out
    }
  }
}
