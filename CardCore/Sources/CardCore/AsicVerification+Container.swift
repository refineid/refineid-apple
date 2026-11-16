// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Reading a ZIP archive as an ASiC-E or BDOC container.
extension AsicVerification {
  /// The media type a BDOC container carries in its `mimetype` entry.
  internal static let bdocMimeType = "application/vnd.bdoc-1.0"

  /// Directory prefix for container signature and manifest entries (EN 319 162-1 clause 4.4.3.1).
  internal static let metaInfPrefix = "META-INF/"

  /// Case-folded form of `metaInfPrefix`.
  private static let foldedMetaInfPrefix = "meta-inf/"

  /// Lowercase extensions of CMS / CAdES signature entries inside `META-INF/`.
  private static let cadesSignatureExtensions = [".p7s", ".p7m", ".p7c"]

  /// Passive metadata filenames permitted directly inside `META-INF/`.
  private static let passiveMetaInfFiles: Set<String> = ["manifest.xml", "container.xml"]

  /// Substring identifying XAdES signature XML entries inside `META-INF/` (EN 319 162-1 §4.4.3.2).
  private static let xadesSignatureNamePart = "signatures"

  /// Substring identifying CAdES signature entries inside `META-INF/` (EN 319 162-1 §4.4.3.2).
  private static let cadesSignatureNamePart = "signature"

  /// Substrings identifying ASiC manifest XML entries inside `META-INF/`.
  private static let manifestNameParts = ["asicmanifest", "asicarchivemanifest"]

  /// Substring identifying RFC 3161 timestamp token entries inside `META-INF/`.
  private static let timestampNamePart = "timestamp"

  private static let xmlExtension = ".xml"
  private static let timestampExtension = ".tst"

  /// The `mimetype` values of the containers this verifier reads.
  private static var knownMimeTypes: [Data] {
    [Data(AsicContainer.mimeType.utf8), Data(Self.bdocMimeType.utf8)]
  }

  /// Every entry of a container whose first entry declares a known
  /// container media type and whose `META-INF/` entries follow EN 319 162-1.
  internal static func containerEntries(_ data: Data) throws -> [String: Data] {
    let archive: ZipReader.Archive
    do {
      archive = try ZipReader.open(data)
    } catch {
      throw DocumentVerification.Failure.unreadable
    }
    guard
      archive.firstEntryName == AsicContainer.mimetypeEntryName,
      archive.firstEntryLocalOffset == ZipValues.firstEntryOffset,
      archive.firstEntryMethod == ZipValues.methodStored,
      (archive.firstEntryFlags ?? .zero) & ZipValues.dataDescriptorFlag == 0,
      archive.firstEntryLocalExtraLength == ZipValues.emptyExtraFieldLength,
      archive.firstEntryCentralExtraLength == ZipValues.emptyExtraFieldLength,
      let mimetype = archive.entries[AsicContainer.mimetypeEntryName],
      Self.knownMimeTypes.contains(mimetype)
    else {
      throw DocumentVerification.Failure.unsupportedProfile
    }
    for dirName in archive.directoryNames {
      try Self.validateContainerDirectoryName(dirName)
    }
    for name in archive.names where name != AsicContainer.mimetypeEntryName {
      try Self.validateContainerEntryName(name)
    }
    try Self.validateMetaInfRoleConsistency(archive.names)
    return archive.entries
  }

  /// Whether `entryName` names an XAdES signature file directly under `META-INF/`.
  internal static func isXadesSignatureEntry(_ entryName: String) -> Bool {
    guard let foldedInside = Self.directMetaInfFileName(entryName) else { return false }
    return foldedInside.hasSuffix(Self.xmlExtension)
      && foldedInside.contains(Self.xadesSignatureNamePart)
  }

  /// Whether `entryName` names a CMS / CAdES signature entry directly under `META-INF/`.
  internal static func isCadesSignatureEntry(_ entryName: String) -> Bool {
    guard let foldedInside = Self.directMetaInfFileName(entryName) else { return false }
    return foldedInside.contains(Self.cadesSignatureNamePart)
      && Self.cadesSignatureExtensions.contains(where: foldedInside.hasSuffix)
  }

  /// Whether `entryName` names a standalone RFC 3161 timestamp entry directly under `META-INF/`.
  internal static func isTimestampAssertionEntry(_ entryName: String) -> Bool {
    guard let foldedInside = Self.directMetaInfFileName(entryName) else { return false }
    return foldedInside.hasSuffix(Self.timestampExtension)
      && foldedInside.contains(Self.timestampNamePart)
  }

  /// Whether `entryName` names an ASiC manifest XML entry directly under `META-INF/`.
  internal static func isAsicManifestEntry(_ entryName: String) -> Bool {
    guard let foldedInside = Self.directMetaInfFileName(entryName) else { return false }
    return foldedInside.hasSuffix(Self.xmlExtension)
      && !foldedInside.contains(Self.xadesSignatureNamePart)
      && Self.manifestNameParts.contains(where: foldedInside.contains)
  }

  /// Ensures any explicit directory under `META-INF/` is the top-level `META-INF/` directory itself.
  private static func validateContainerDirectoryName(_ name: String) throws {
    guard name.lowercased().hasPrefix(Self.foldedMetaInfPrefix) else { return }
    guard name == Self.metaInfPrefix else {
      throw DocumentVerification.Failure.unreadable
    }
  }

  /// Rejects orphan `ASiCManifest` / `ASiCArchiveManifest` entries with no accompanying CAdES or `.tst` entry.
  private static func validateMetaInfRoleConsistency(_ names: [String]) throws {
    let hasManifest = names.contains(where: Self.isAsicManifestEntry)
    guard hasManifest else { return }
    let hasCoveringAssertion = names.contains { name in
      Self.isCadesSignatureEntry(name) || Self.isTimestampAssertionEntry(name)
    }
    guard hasCoveringAssertion else {
      throw DocumentVerification.Failure.unreadable
    }
  }

  /// Ensures `META-INF/` casing is exact, flat, and holds only recognized container metadata.
  private static func validateContainerEntryName(_ name: String) throws {
    let folded = name.lowercased()
    guard folded.hasPrefix(Self.foldedMetaInfPrefix) else { return }
    guard
      let foldedInside = Self.directMetaInfFileName(name),
      Self.isRecognizedMetaInfFile(foldedInside)
    else {
      throw DocumentVerification.Failure.unreadable
    }
  }

  /// Lowercase filename directly inside `META-INF/`, nil when outside `META-INF/`, miscased, or nested.
  private static func directMetaInfFileName(_ entryName: String) -> String? {
    guard entryName.hasPrefix(Self.metaInfPrefix) else { return nil }
    let inside = entryName.dropFirst(Self.metaInfPrefix.count)
    guard !inside.isEmpty, !inside.contains("/") else { return nil }
    return inside.lowercased()
  }

  /// Whether `foldedInside` is a signature, manifest, timestamp, or passive metadata file in `META-INF/`.
  private static func isRecognizedMetaInfFile(_ foldedInside: String) -> Bool {
    if Self.passiveMetaInfFiles.contains(foldedInside) {
      return true
    }
    if foldedInside.hasSuffix(Self.xmlExtension) {
      return foldedInside.contains(Self.xadesSignatureNamePart)
        || Self.manifestNameParts.contains(where: foldedInside.contains)
    }
    if Self.cadesSignatureExtensions.contains(where: foldedInside.hasSuffix) {
      return foldedInside.contains(Self.cadesSignatureNamePart)
    }
    if foldedInside.hasSuffix(Self.timestampExtension) {
      return foldedInside.contains(Self.timestampNamePart)
    }
    return false
  }
}
