// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing
import zlib

@testable import CardCore

/// Hardening tests for ZIP entry paths, archive tiling, `META-INF/` roles, `FlateDecoder`, and `B-LTA` coverage.
@Suite
internal struct AsicContainerHardeningTests {
  /// Standard IEEE 802.3 CRC-32 check value for ASCII `"123456789"`.
  private static let ieeeCheckValue: UInt32 = 0xCBF4_3926
  private static let ieeeCheckInput = Data("123456789".utf8)

  private static let invalidEntryNames = [
    "META-INF/../contract.pdf",
    "./contract.pdf",
    "/contract.pdf",
    "folder\\contract.pdf",
    "folder//contract.pdf",
    "contract\u{0000}.pdf",
    "contract\u{001F}.pdf",
  ]

  private static let rejectedMetaInfEntries = [
    "META-INF/payload.pdf",
    "META-INF/evil.xml",
    "META-INF/signature0.xml",
    "META-INF/ASiCManifest.xml",
    "META-INF/sub/signatures0.xml",
    "meta-inf/signatures0.xml",
  ]

  /// Compresses `content` with RFC 1950 zlib framing.
  private static func zlibDeflate(_ content: Data) throws -> Data {
    var stream = z_stream()
    guard
      deflateInit_(
        &stream, Z_DEFAULT_COMPRESSION, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)
      ) == Z_OK
    else {
      throw SyntheticZipArchive.Failure.deflate
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
    guard let produced else { throw SyntheticZipArchive.Failure.deflate }
    return Data(output.prefix(produced))
  }

  @Test
  internal func pathTraversalAndNonPlainEntryNamesAreRefused() throws {
    let signed = try AsicVerificationTests.signedDocument(profile: .ecdsaP384)
    for badName in Self.invalidEntryNames {
      let archive = SyntheticZipArchive(entries: [
        .stored(AsicContainer.mimetypeEntryName, Data(AsicContainer.mimeType.utf8)),
        .stored("test.txt", Data("Sample text content to be signed.".utf8)),
        .stored("invoice.pdf", Data("Simulated PDF invoice data.".utf8)),
        .stored(AsicVerificationTests.signatureFileName, Data(signed.document.utf8)),
        .stored(badName, Data("injected unsigned payload".utf8)),
      ]).encoded

      #expect(throws: ZipReader.Failure.invalidEntryName) {
        _ = try ZipReader.open(archive)
      }
      #expect(throws: DocumentVerification.Failure.unreadable) {
        _ = try AsicVerification.verify(container: archive, anchors: .empty)
      }
    }
  }

  @Test
  internal func unindexedLocalHeaderAndTrailingBytesAreRefused() throws {
    var writer = AsicContainer.ZipWriter()
    writer.add(name: AsicContainer.mimetypeEntryName, content: Data(AsicContainer.mimeType.utf8))
    writer.add(name: "test.txt", content: Data("hello".utf8))
    let clean = try #require(writer.finish())

    var trailing = clean
    trailing.append(contentsOf: Data("trailing".utf8))
    #expect(throws: ZipReader.Failure.malformed) {
      _ = try ZipReader.open(trailing)
    }

    // Splice an unindexed local entry immediately before the central directory and shift EOCD's directoryOffset.
    var hiddenWriter = AsicContainer.ZipWriter()
    hiddenWriter.add(name: "hidden.txt", content: Data("unindexed local entry".utf8))
    let hiddenArchive = try #require(hiddenWriter.finish())
    let hiddenEocd = hiddenArchive.count - ZipValues.eocdRecordLength
    let hiddenDirOffset = Int(
      ZipReader.readUInt32(
        from: hiddenArchive, at: hiddenEocd + ZipValues.eocdDirectoryOffsetOffset)
    )
    let unindexedLocalRecord = hiddenArchive.prefix(hiddenDirOffset)

    let cleanEocd = clean.count - ZipValues.eocdRecordLength
    let cleanDirOffset = Int(
      ZipReader.readUInt32(from: clean, at: cleanEocd + ZipValues.eocdDirectoryOffsetOffset))
    var spliced = Data(clean.prefix(cleanDirOffset))
    spliced.append(unindexedLocalRecord)
    let newDirOffset = UInt32(spliced.count)
    spliced.append(clean.subdata(in: cleanDirOffset..<clean.count))
    let splicedEocd = spliced.count - ZipValues.eocdRecordLength
    let offsetFieldStart = splicedEocd + ZipValues.eocdDirectoryOffsetOffset
    withUnsafeBytes(of: newDirOffset.littleEndian) { raw in
      spliced.replaceSubrange(
        offsetFieldStart..<(offsetFieldStart + MemoryLayout<UInt32>.size), with: raw)
    }

    #expect(throws: ZipReader.Failure.malformed) {
      _ = try ZipReader.open(spliced)
    }
  }

  @Test
  internal func unknownOrNestedMetaInfEntriesAreRefused() throws {
    let signed = try AsicVerificationTests.signedDocument(profile: .ecdsaP384)
    for badEntry in Self.rejectedMetaInfEntries {
      var writer = AsicContainer.ZipWriter()
      writer.add(name: AsicContainer.mimetypeEntryName, content: Data(AsicContainer.mimeType.utf8))
      for object in AsicVerificationTests.sampleObjects() {
        writer.add(name: object.name, content: object.content)
      }
      if badEntry.lowercased() != AsicVerificationTests.signatureFileName.lowercased() {
        writer.add(
          name: AsicVerificationTests.signatureFileName, content: Data(signed.document.utf8))
      }
      writer.add(name: badEntry, content: Data(signed.document.utf8))
      let archive = try #require(writer.finish())

      #expect(throws: DocumentVerification.Failure.unreadable) {
        _ = try AsicVerification.verify(container: archive, anchors: .empty)
      }
    }
  }

  @Test
  internal func zlibCrc32AndFlateDecoderRoundTripAndEnforceLimits() throws {
    #expect(AsicContainer.ZipWriter.crc32(Data()) == 0)
    #expect(AsicContainer.ZipWriter.crc32(Self.ieeeCheckInput) == Self.ieeeCheckValue)

    let sample = Data(repeating: UInt8(ascii: "A"), count: 1_024) + Self.ieeeCheckInput
    let wrapped = try Self.zlibDeflate(sample)
    #expect(FlateDecoder.decoded(wrapped, limit: sample.count) == sample)
    #expect(FlateDecoder.decoded(wrapped, limit: sample.count - 1) == nil)
  }

  @Test
  internal func directoryOrderAndMetaInfDirectoriesFollowContainerRules() throws {
    let signed = try AsicVerificationTests.signedDocument(profile: .ecdsaP384)
    let mimetype = SyntheticZipArchive.Entry.stored(
      AsicContainer.mimetypeEntryName, Data(AsicContainer.mimeType.utf8))
    let leadingDirArchive = SyntheticZipArchive(entries: [
      .directory("docs/"),
      mimetype,
      .stored("docs/test.txt", Data("hello".utf8)),
    ]).encoded
    #expect(!AsicVerification.isAsicContainer(leadingDirArchive))
    #expect(throws: DocumentVerification.Failure.unsupportedProfile) {
      _ = try AsicVerification.verify(container: leadingDirArchive, anchors: .empty)
    }

    var validEntries: [SyntheticZipArchive.Entry] = [
      mimetype,
      .directory(AsicVerification.metaInfPrefix),
    ]
    for object in AsicVerificationTests.sampleObjects() {
      validEntries.append(.stored(object.name, object.content))
    }
    validEntries.append(
      .stored(AsicVerificationTests.signatureFileName, Data(signed.document.utf8)))
    let validReport = try AsicVerificationTests.report(
      SyntheticZipArchive(entries: validEntries).encoded)
    #expect(validReport.documentIntact)
    #expect(validReport.signatureValid)

    for badDir in ["meta-inf/", "META-INF/sub/"] {
      let invalidDirArchive = SyntheticZipArchive(entries: [
        mimetype,
        .directory(badDir),
        .stored("test.txt", Data("hello".utf8)),
      ]).encoded
      #expect(throws: DocumentVerification.Failure.unreadable) {
        _ = try AsicVerification.verify(container: invalidDirArchive, anchors: .empty)
      }
    }
  }

  @Test
  internal func nonAsciiEntryNameRequiresUtf8FlagAndTimestampEntryBlocksValidity() throws {
    let mimetype = SyntheticZipArchive.Entry.stored(
      AsicContainer.mimetypeEntryName, Data(AsicContainer.mimeType.utf8))
    let nonAsciiUnflagged = SyntheticZipArchive.Entry.stored(
      "sopimus-ä.pdf", Data("payload".utf8))
    #expect(throws: ZipReader.Failure.malformed) {
      _ = try ZipReader.open(SyntheticZipArchive(entries: [mimetype, nonAsciiUnflagged]).encoded)
    }

    var nonAsciiFlagged = nonAsciiUnflagged
    nonAsciiFlagged.flags = ZipValues.utf8NameFlag
    let opened = try ZipReader.open(
      SyntheticZipArchive(entries: [mimetype, nonAsciiFlagged]).encoded)
    #expect(opened.entries["sopimus-ä.pdf"] == Data("payload".utf8))

    let tstOnly = SyntheticZipArchive(entries: [
      mimetype,
      .stored("test.txt", Data("hello".utf8)),
      .stored("META-INF/ASiCManifest.xml", Data("<asic:ASiCManifest/>".utf8)),
      .stored("META-INF/timestamp.tst", Data("simulated timestamp token".utf8)),
    ]).encoded
    let tstReport = try AsicVerification.verify(container: tstOnly, anchors: .empty)
    #expect(tstReport.signatures.count == 1)
    #expect(!tstReport.isValid)
  }
}
