// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// One name resolves to one set of bytes (EN 319 162-1 clause 5.2), and
/// declared sizes are bounded and true.
extension ZipReaderTests {
  /// A synthetic payload.
  private static let payload = Data("Synthetic entry content.".utf8)

  /// A synthetic entry name.
  private static let entryName = "data.txt"

  /// The same name, spelled with different case.
  private static let foldedEntryName = "Data.txt"

  /// Another synthetic entry name.
  private static let otherEntryName = "other.txt"

  /// The difference between a false declared value and the true one.
  private static let skew: UInt32 = 1

  /// The refusal `entries` meets, or nil when the archive reads.
  private static func refusal(_ entries: [SyntheticZipArchive.Entry]) -> ZipReader.Failure? {
    do {
      _ = try ZipReader.open(SyntheticZipArchive(entries: entries).encoded)
      return nil
    } catch let failure as ZipReader.Failure {
      return failure
    } catch {
      Issue.record("Unexpected error: \(error)")
      return nil
    }
  }

  @Test
  internal func truthfulStoredAndDeflatedEntriesRead() throws {
    let archive = try ZipReader.open(
      SyntheticZipArchive(entries: [
        .stored(Self.entryName, Self.payload),
        try .deflated(Self.otherEntryName, Self.payload),
      ]).encoded
    )
    #expect(archive.names == [Self.entryName, Self.otherEntryName])
    #expect(archive.entries[Self.entryName] == Self.payload)
    #expect(archive.entries[Self.otherEntryName] == Self.payload)
  }

  @Test
  internal func duplicateNameIsRefused() {
    #expect(
      Self.refusal([
        .stored(Self.entryName, Self.payload), .stored(Self.entryName, Self.payload),
      ]) == .duplicateName
    )
  }

  @Test
  internal func caseFoldedDuplicateNameIsRefused() {
    #expect(
      Self.refusal([
        .stored(Self.entryName, Self.payload), .stored(Self.foldedEntryName, Self.payload),
      ]) == .duplicateName
    )
  }

  @Test
  internal func declaredSizeOverTheCeilingIsRefused() {
    let overCeiling = UInt32(ZipValues.maximumEntryByteCount) + Self.skew
    var entry = SyntheticZipArchive.Entry.stored(Self.entryName, Self.payload)
    entry.uncompressedSize = overCeiling
    #expect(Self.refusal([entry]) == .sizeOverCeiling)
    var compressed = SyntheticZipArchive.Entry.stored(Self.entryName, Self.payload)
    compressed.compressedSize = overCeiling
    #expect(Self.refusal([compressed]) == .sizeOverCeiling)
  }

  @Test
  internal func declaredTotalOverTheCeilingIsRefused() {
    var first = SyntheticZipArchive.Entry.stored(Self.entryName, Self.payload)
    first.uncompressedSize = UInt32(ZipValues.maximumEntryByteCount)
    var second = SyntheticZipArchive.Entry.stored(Self.otherEntryName, Self.payload)
    second.uncompressedSize = Self.skew
    #expect(Self.refusal([first, second]) == .sizeOverCeiling)
  }

  @Test
  internal func crcMismatchIsRefused() {
    var entry = SyntheticZipArchive.Entry.stored(Self.entryName, Self.payload)
    entry.crc ^= Self.skew
    #expect(Self.refusal([entry]) == .crcMismatch)
  }

  @Test
  internal func localAndCentralNameDisagreementIsRefused() {
    var entry = SyntheticZipArchive.Entry.stored(Self.entryName, Self.payload)
    entry.localName = Self.otherEntryName
    #expect(Self.refusal([entry]) == .nameMismatch)
  }

  @Test
  internal func inflatedLengthDifferentFromDeclaredIsRefused() throws {
    var longer = try SyntheticZipArchive.Entry.deflated(Self.entryName, Self.payload)
    longer.uncompressedSize += Self.skew
    #expect(Self.refusal([longer]) == .lengthMismatch)
    var shorter = try SyntheticZipArchive.Entry.deflated(Self.entryName, Self.payload)
    shorter.uncompressedSize -= Self.skew
    #expect(Self.refusal([shorter]) == .lengthMismatch)
  }

  @Test
  internal func storedSizesThatDisagreeAreRefused() {
    var entry = SyntheticZipArchive.Entry.stored(Self.entryName, Self.payload)
    entry.uncompressedSize += Self.skew
    #expect(Self.refusal([entry]) == .lengthMismatch)
  }

  @Test
  internal func lengthsPastTheArchiveEndAreRefused() {
    var entry = SyntheticZipArchive.Entry.stored(Self.entryName, Self.payload)
    entry.declaredCommentLength = UInt16.max
    #expect(Self.refusal([entry]) == .malformed)
  }
}
