// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// CAdES signature entries inside ASiC-E and BDOC containers surface as
/// `unsupported` rows that block `DocumentReport.isValid`.
extension AsicVerificationTests {
  @Test
  internal func reportsCadesEntriesAsUnsupportedInMixedContainer() throws {
    let signed = try Self.signedDocument(profile: .ecdsaP384)
    let container = try Self.container(document: signed.document)
    var entries = ZipReader.read(archive: container)
    let cadesEntryNames = [
      "META-INF/signature001.p7s",
      "META-INF/SIGNATURE002.P7M",
    ]
    entries["META-INF/ASiCManifest001.xml"] = Data("<asic:ASiCManifest/>".utf8)
    for name in cadesEntryNames {
      entries[name] = Data("simulated CAdES signature".utf8)
    }

    let mixedContainer = try Self.reassembled(entries)
    let report = try DocumentVerification.verify(document: mixedContainer, anchors: .empty)

    #expect(report.signatures.count == 1 + cadesEntryNames.count)
    #expect(report.judged.count == 1)
    #expect(report.judged[0].documentIntact)
    #expect(report.judged[0].signatureValid)
    let unsupportedCount = report.signatures.reduce(into: 0) { count, entry in
      if case .unsupported = entry {
        count += 1
      }
    }
    #expect(unsupportedCount == cadesEntryNames.count)
    #expect(!report.isValid)
  }

  @Test
  internal func reportsCadesOnlyContainerAsUnsupportedInsteadOfNoSignatures() throws {
    let containers = [
      (mimeType: AsicContainer.mimeType, signatureEntry: "META-INF/signature.p7s"),
      (mimeType: AsicVerification.bdocMimeType, signatureEntry: "META-INF/signature0.p7c"),
    ]

    for fixture in containers {
      var writer = AsicContainer.ZipWriter()
      writer.add(name: AsicContainer.mimetypeEntryName, content: Data(fixture.mimeType.utf8))
      writer.add(name: "file.txt", content: Data("hello".utf8))
      writer.add(
        name: "META-INF/ASiCManifest.xml",
        content: Data("<asic:ASiCManifest/>".utf8)
      )
      writer.add(
        name: fixture.signatureEntry,
        content: Data("simulated CAdES signature".utf8)
      )
      let archive = try #require(writer.finish())

      let report = try DocumentVerification.verify(document: archive, anchors: .empty)
      #expect(report.signatures.count == 1)
      #expect(report.judged.isEmpty)
      guard case .unsupported = report.signatures[0] else {
        Issue.record("Expected unsupported signature entry for \(fixture.signatureEntry)")
        return
      }
      #expect(!report.isValid)
    }
  }
}
