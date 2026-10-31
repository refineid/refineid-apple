// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// An archive is a container only when its first entry is a stored
/// `mimetype` naming a known container type (EN 319 162-1 clause A.1).
@Suite
internal struct AsicContainerReadingTests {
  /// A synthetic data object.
  private static let dataObject = SyntheticZipArchive.Entry.stored(
    "data.txt", Data("Synthetic data object.".utf8))

  /// A media type no container reader knows.
  private static let unknownMimeType = "application/zip"

  /// An end-of-line after the media type.
  private static let lineFeed = "\n"

  /// A signature file name, and the same name case-folded.
  private static let upperSignatureFileName = "META-INF/Signatures0.xml"
  private static let lowerSignatureFileName = "META-INF/signatures0.xml"

  /// Synthetic extra-field bytes.
  private static let extraField = "synthetic"

  /// Synthetic signature file content.
  private static let signaturesXml = "<signatures/>"

  /// The `mimetype` entry holding `value`, stored.
  private static func mimetype(_ value: String) -> SyntheticZipArchive.Entry {
    .stored(AsicContainer.mimetypeEntryName, Data(value.utf8))
  }

  /// What reading `entries` as a container throws, or nil.
  private static func failure(
    _ entries: [SyntheticZipArchive.Entry]
  ) -> DocumentVerification.Failure? {
    do {
      _ = try AsicVerification.containerEntries(SyntheticZipArchive(entries: entries).encoded)
      return nil
    } catch let failure as DocumentVerification.Failure {
      return failure
    } catch {
      Issue.record("Unexpected error: \(error)")
      return nil
    }
  }

  /// A valid archive is a container; the same entries without the
  /// mimetype are not.
  @Test
  internal func validArchiveIsAnAsicContainer() {
    let valid = SyntheticZipArchive(
      entries: [Self.mimetype(AsicContainer.mimeType), Self.dataObject]
    ).encoded
    #expect(AsicVerification.isAsicContainer(valid))
    #expect(
      !AsicVerification.isAsicContainer(SyntheticZipArchive(entries: [Self.dataObject]).encoded))
  }

  /// A container without signature files carries no signatures.
  @Test
  internal func containerWithoutSignatureFilesHasNoSignatures() {
    let container = SyntheticZipArchive(
      entries: [Self.mimetype(AsicContainer.mimeType), Self.dataObject]
    ).encoded
    #expect(throws: DocumentVerification.Failure.noSignatures) {
      _ = try DocumentVerification.verify(document: container)
    }
  }

  /// Signature file names equal after case folding make the archive
  /// unreadable.
  @Test
  internal func caseFoldedSignatureFileNamesAreUnreadable() {
    let upper = SyntheticZipArchive.Entry.stored(
      Self.upperSignatureFileName, Data(Self.signaturesXml.utf8))
    let lower = SyntheticZipArchive.Entry.stored(
      Self.lowerSignatureFileName, Data(Self.signaturesXml.utf8))
    #expect(
      Self.failure([Self.mimetype(AsicContainer.mimeType), Self.dataObject, upper, lower])
        == .unreadable)
  }

  @Test
  internal func asicAndBdocMimetypesAreContainers() {
    #expect(Self.failure([Self.mimetype(AsicContainer.mimeType), Self.dataObject]) == nil)
    #expect(Self.failure([Self.mimetype(AsicVerification.bdocMimeType), Self.dataObject]) == nil)
  }

  @Test
  internal func zipWithoutMimetypeIsUnsupported() {
    #expect(Self.failure([Self.dataObject]) == .unsupportedProfile)
  }

  @Test
  internal func unknownMimetypeValueIsUnsupported() {
    #expect(
      Self.failure([Self.mimetype(Self.unknownMimeType), Self.dataObject]) == .unsupportedProfile
    )
  }

  @Test
  internal func mimetypeWithTrailingNewlineIsUnsupported() {
    #expect(
      Self.failure([Self.mimetype(AsicContainer.mimeType + Self.lineFeed), Self.dataObject])
        == .unsupportedProfile
    )
  }

  @Test
  internal func mimetypeNotFirstIsUnsupported() {
    #expect(
      Self.failure([Self.dataObject, Self.mimetype(AsicContainer.mimeType)])
        == .unsupportedProfile
    )
  }

  @Test
  internal func deflatedMimetypeIsUnsupported() throws {
    let deflated = try SyntheticZipArchive.Entry.deflated(
      AsicContainer.mimetypeEntryName, Data(AsicContainer.mimeType.utf8))
    #expect(Self.failure([deflated, Self.dataObject]) == .unsupportedProfile)
  }

  @Test
  internal func refusedArchiveIsUnreadable() {
    #expect(
      Self.failure([Self.mimetype(AsicContainer.mimeType), Self.dataObject, Self.dataObject])
        == .unreadable
    )
  }

  @Test
  internal func zipWithoutMimetypeIsNotAContainer() {
    let archive = SyntheticZipArchive(entries: [Self.dataObject]).encoded
    #expect(!AsicVerification.isAsicContainer(archive))
  }

  @Test
  internal func mimetypeWithLocalExtraFieldIsUnsupported() {
    var mimetype = Self.mimetype(AsicContainer.mimeType)
    mimetype.localExtra = Data(Self.extraField.utf8)
    #expect(Self.failure([mimetype, Self.dataObject]) == .unsupportedProfile)
  }
}
