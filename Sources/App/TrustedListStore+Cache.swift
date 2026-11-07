// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoKit
import Foundation

/// The cache: one index of records and one file of raw bytes per list.
extension TrustedListStore {
  /// The index file's name.
  nonisolated internal static let indexFileName = "index.json"

  /// The extension of a list's bytes file.
  nonisolated private static let listFileExtension = "xml"

  /// The lists the cache holds, read and verified again; nil when there
  /// is no cache or it does not read.
  nonisolated internal static func cachedLists(_ dependencies: Dependencies) -> TrustedLists? {
    let directory = dependencies.directory
    guard
      let indexData = try? Data(contentsOf: directory.appending(path: Self.indexFileName)),
      let records = try? JSONDecoder().decode([TrustedListCacheRecord].self, from: indexData)
    else {
      return nil
    }
    let cached = records.compactMap { record -> TrustedLists.CachedList? in
      guard let bytes = try? Data(contentsOf: directory.appending(path: record.file)) else {
        return nil
      }
      return TrustedLists.CachedList(
        location: record.location, fetchedAt: record.fetchedAt, nextUpdate: record.nextUpdate,
        bytes: bytes)
    }
    do {
      return try dependencies.reader.cached(cached)
    } catch {
      #if DEBUG
        DevErrorLog.report(
          "trusted list cache refused: \(DevErrorLog.reason(error))", source: .app)
      #endif
      return nil
    }
  }

  /// Writes `cache` as the whole cache: every list's bytes, then the
  /// index; a list that fails to write is left out of the index.
  nonisolated internal static func store(
    _ cache: [TrustedLists.CachedList],
    in directory: URL
  ) {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      // The lists are public and fetched again at will; a backup need
      // not carry them.
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var excluded = directory
      try excluded.setResourceValues(values)
    } catch {
      Self.reportCacheFailure(error)
      return
    }
    var records: [TrustedListCacheRecord] = []
    for list in cache {
      let file = Self.fileName(for: list.location)
      do {
        try list.bytes.write(to: directory.appending(path: file), options: .atomic)
      } catch {
        Self.reportCacheFailure(error)
        continue
      }
      records.append(
        TrustedListCacheRecord(
          location: list.location, fetchedAt: list.fetchedAt, nextUpdate: list.nextUpdate,
          file: file))
    }
    do {
      let index = try JSONEncoder().encode(records)
      try index.write(to: directory.appending(path: Self.indexFileName), options: .atomic)
    } catch {
      Self.reportCacheFailure(error)
    }
  }

  /// The file a list at `location` is stored in: the SHA-256 of the
  /// location in lowercase hexadecimal, so no location reaches the file
  /// system as a path.
  nonisolated internal static func fileName(for location: String) -> String {
    let digest = SHA256.hash(data: Data(location.utf8))
    return digest.map { byte in String(format: "%02x", byte) }.joined() + "."
      + Self.listFileExtension
  }

  /// Reports one cache write failure in a development build.
  nonisolated private static func reportCacheFailure(_ error: any Error) {
    #if DEBUG
      DevErrorLog.report(
        "trusted list cache write failed: \(DevErrorLog.reason(error))", source: .app)
    #endif
  }
}
