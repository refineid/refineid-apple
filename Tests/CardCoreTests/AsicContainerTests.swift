// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// The ASiC-E archive writer: entry order, the mimetype rule, and the
/// unsigned inventory.
@Suite
internal struct AsicContainerTests {
  /// One placeholder file to carry.
  private static func sample() -> [AsicContainer.DataObject] {
    let object = AsicContainer.DataObject(
      name: "dossier.pdf",
      mimeType: "application/pdf",
      content: Data("a set of statements worth signing".utf8)
    )
    return [object]
  }

  /// Decoded UTF-8, failing the test on undecodable bytes.
  private static func text(_ data: Data) throws -> String {
    try #require(String(bytes: data, encoding: .utf8))
  }

  /// One `unzip` run against the scratch directory.
  private static func unzip(_ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()
    let report = try Self.text(
      pipe.fileHandleForReading.readDataToEndOfFile()
    )
    try #require(process.terminationStatus == 0, "unzip failed: \(report)")
    return report
  }

  /// One file under a given name, with content that does not matter.
  private static func named(_ name: String) -> AsicContainer.DataObject {
    AsicContainer.DataObject(
      name: name, mimeType: "application/octet-stream", content: Data("x".utf8)
    )
  }

  @Test
  internal func crc32MatchesTheKnownCheckValue() {
    // The standard CRC-32 check value for "123456789".
    #expect(
      AsicContainer.ZipWriter.crc32(Data("123456789".utf8)) == 0xCBF4_3926
    )
    #expect(AsicContainer.ZipWriter.crc32(Data()) == 0)
  }

  @Test
  internal func mimetypeIsFirstAndStoredAtAFixedOffset() throws {
    let archive = try #require(
      AsicContainer.container(
        objects: Self.sample(),
        signatureXml: Data("not really a signature".utf8)
      )
    )
    // A reader identifies the container by the bytes right after the
    // first local header: the entry name, then the media type.
    let nameStart = ZipValues.localHeaderLength
    let nameEnd = nameStart + AsicContainer.mimetypeEntryName.utf8.count
    #expect(
      archive[nameStart..<nameEnd]
        == Data(AsicContainer.mimetypeEntryName.utf8)
    )
    let mediaEnd = nameEnd + AsicContainer.mimeType.utf8.count
    #expect(archive[nameEnd..<mediaEnd] == Data(AsicContainer.mimeType.utf8))
  }

  @Test
  internal func everyExpectedEntryIsPresent() throws {
    let archive = try #require(
      AsicContainer.container(
        objects: Self.sample(),
        signatureXml: Data("signature".utf8)
      )
    )
    for entry in [
      AsicContainer.mimetypeEntryName,
      "dossier.pdf",
      AsicContainer.manifestEntryName,
      AsicContainer.signatureEntryName,
    ] {
      #expect(
        archive.firstRange(of: Data(entry.utf8)) != nil,
        "missing entry \(entry)"
      )
    }
  }

  @Test
  internal func tooManyEntriesAreRefusedBeforeTheCountWraps() {
    var writer = AsicContainer.ZipWriter()
    for index in 0...Int(UInt16.max) {
      writer.add(name: "entry-\(index)", content: Data())
    }
    // The 65536th entry overflowed the 16-bit count; the writer must
    // refuse to produce an archive that misdescribes itself.
    #expect(writer.finish() == nil)
  }

  @Test
  internal func theInventoryNamesTheContainerFirstAndEveryFile() throws {
    let manifest = try Self.text(AsicContainer.manifest(Self.sample()))
    #expect(
      manifest.contains(
        #"manifest:full-path="/" "#
          + #"manifest:media-type="\#(AsicContainer.mimeType)""#
      )
    )
    #expect(manifest.contains(#"manifest:full-path="dossier.pdf""#))
    #expect(manifest.contains(#"manifest:media-type="application/pdf""#))
  }

  /// A name reaches the inventory as a package path, XML-escaped and not percent-encoded.
  @Test
  internal func namesAreXmlEscapedInManifest() throws {
    let object = AsicContainer.DataObject(
      name: "a&b\"c#d e.pdf",
      mimeType: "application/pdf",
      content: Data("x".utf8)
    )
    let manifest = try Self.text(AsicContainer.manifest([object]))
    #expect(
      manifest.contains(#"manifest:full-path="a&amp;b&quot;c#d e.pdf""#),
      "name must be XML-escaped: \(manifest)"
    )
  }

  /// A media type is not a URI: it is XML-escaped and not encoded.
  @Test
  internal func mediaTypesAreEscapedButNotEncoded() throws {
    let object = AsicContainer.DataObject(
      name: "a.bin",
      mimeType: "text/plain; x=\"1&2\"",
      content: Data("x".utf8)
    )
    let manifest = try Self.text(AsicContainer.manifest([object]))
    #expect(
      manifest.contains(
        #"manifest:media-type="text/plain; x=&quot;1&amp;2&quot;""#
      ),
      "\(manifest)"
    )
  }

  /// The archive read back by a tool that is not ours.
  ///
  /// `unzip` walks the central directory, checks every CRC, and
  /// extracts. If it agrees, the offsets and checksums are right.
  @Test
  internal func unzipReadsAndVerifiesTheContainer() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("asic-container-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let dossier = Data("RefineID ASiC interoperability dossier".utf8)
    let objects = [
      AsicContainer.DataObject(
        name: "dossier.pdf", mimeType: "application/pdf", content: dossier
      ),
      AsicContainer.DataObject(
        name: "annex.txt",
        mimeType: "text/plain",
        content: Data("annex one, completed and signed".utf8)
      ),
    ]
    let archive = try #require(
      AsicContainer.container(
        objects: objects, signatureXml: Data("placeholder".utf8)
      )
    )
    let container = directory.appendingPathComponent("out.asice")
    try archive.write(to: container)

    // Every CRC and every offset, checked by an outside reader.
    let report = try Self.unzip(["-t", container.path])
    #expect(report.contains("No errors detected"), "\(report)")

    // The entries come back byte-identical.
    _ = try Self.unzip(["-o", "-q", container.path, "-d", directory.path])
    let extracted = try Data(
      contentsOf: directory.appendingPathComponent("dossier.pdf")
    )
    #expect(extracted == dossier)
    let mimetype = try Data(
      contentsOf: directory.appendingPathComponent(
        AsicContainer.mimetypeEntryName
      )
    )
    #expect(mimetype == Data(AsicContainer.mimeType.utf8))
  }

  /// Ordinary names, including a subfolder, are carried as they are.
  @Test
  internal func usableNamesArePassed() {
    let names = ["dossier.pdf", "annex one.txt", "appendix/figure.png", "mimetypes.txt"]
    #expect(AsicContainer.areNamesUsable(names.map(Self.named)))
  }

  /// Names a container cannot carry, each refused on its own.
  ///
  /// `mimetype` and `META-INF/` belong to the container, and the rest
  /// have no single portable meaning once the archive is unpacked - a
  /// file under any of them could displace a manifest or a signature.
  @Test(arguments: [
    "mimetype",
    "MimeType",
    "META-INF",
    "META-INF/manifest.xml",
    "meta-inf/signatures0.xml",
    "/absolute.pdf",
    "../escaping.pdf",
    "sub/../escaping.pdf",
    "back\\slash.pdf",
    "line\nbreak.pdf",
    "",
  ])
  internal func unusableNamesAreRefused(name: String) {
    #expect(!AsicContainer.areNamesUsable([Self.named(name)]))
    #expect(
      AsicContainer.container(
        objects: [Self.named(name)], signatureXml: Data("signature".utf8)
      ) == nil
    )
  }

  /// Two files cannot share one entry name: the archive would carry
  /// both and the signature would reference one URI twice, leaving a
  /// reader to choose which entry it attests.
  @Test
  internal func repeatedNamesAreRefused() {
    let objects = [Self.named("report.pdf"), Self.named("report.pdf")]
    #expect(!AsicContainer.areNamesUsable(objects))
    #expect(
      AsicContainer.container(
        objects: objects, signatureXml: Data("signature".utf8)
      ) == nil
    )
  }
}
