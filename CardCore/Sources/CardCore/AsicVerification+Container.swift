// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Reading a ZIP archive as an ASiC-E or BDOC container.
extension AsicVerification {
  /// The media type a BDOC container carries in its `mimetype` entry.
  internal static let bdocMimeType = "application/vnd.bdoc-1.0"

  /// The `mimetype` values of the containers this verifier reads.
  private static var knownMimeTypes: [Data] {
    [Data(AsicContainer.mimeType.utf8), Data(Self.bdocMimeType.utf8)]
  }

  /// Every entry of a container whose first entry declares a known
  /// container media type.
  ///
  /// EN 319 162-1 clause A.1: the `mimetype` entry is the first entry
  /// of the archive, stored without compression, with no extra field
  /// in its local header, and holds the media type exactly. An archive the ZIP reader refuses is unreadable; a
  /// readable archive without such an entry is not a supported
  /// container.
  internal static func containerEntries(_ data: Data) throws -> [String: Data] {
    let archive: ZipReader.Archive
    do {
      archive = try ZipReader.open(data)
    } catch {
      throw DocumentVerification.Failure.unreadable
    }
    guard
      archive.names.first == AsicContainer.mimetypeEntryName,
      archive.firstEntryLocalOffset == ZipValues.firstEntryOffset,
      archive.firstEntryMethod == ZipValues.methodStored,
      archive.firstEntryLocalExtraLength == ZipValues.emptyExtraFieldLength,
      let mimetype = archive.entries[AsicContainer.mimetypeEntryName],
      Self.knownMimeTypes.contains(mimetype)
    else {
      throw DocumentVerification.Failure.unsupportedProfile
    }
    return archive.entries
  }
}
