// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore
@testable import RefineIDTestHost

/// A fetch that reads no national list fails instead of caching a
/// husk, and stored anchors with nothing in them are fetched again.
@MainActor
@Suite
internal struct TrustedListHuskCacheTests {
  /// A reader whose national lists never read: the list of the lists
  /// verifies, every national outcome fails.
  private struct HuskReader: TrustedListReader, Sendable {
    let lotlBytes: Data
    let nationalLocation: String
    let nextUpdate: Date?
    let now: Date

    func listOfTheLists(_ bytes: Data) throws -> TrustedList {
      guard bytes == lotlBytes else { throw TrustedListError.signatureInvalid }
      return TrustedList(
        kind: .euListOfTheLists, territory: "EU", operatorName: "Operator",
        issuedAt: now, nextUpdate: nextUpdate, pointers: [], services: [], signer: Data())
    }

    func lists(
      listOfTheLists bytes: Data,
      national _: (String) -> Data?,
      fetchedAt: Date
    ) throws -> TrustedLists.Reading {
      let lotl = try listOfTheLists(bytes)
      let failed = TrustedLists.NationalList(
        territory: TrustedListStoreTests.territory, location: nationalLocation,
        outcome: .failure(.notFetched))
      return TrustedLists.Reading(
        lists: TrustedLists(listOfTheLists: lotl, national: [failed], fetchedAt: fetchedAt),
        cache: [
          TrustedLists.CachedList(
            location: TrustedLists.listOfTheListsLocation, fetchedAt: fetchedAt,
            nextUpdate: nextUpdate, bytes: bytes)
        ])
    }

    func cached(_ records: [TrustedLists.CachedList]) throws -> TrustedLists {
      guard records.contains(where: { $0.location == TrustedLists.listOfTheListsLocation }) else {
        throw TrustedListError.notFetched
      }
      return try lists(
        listOfTheLists: lotlBytes,
        national: { _ in nil },
        fetchedAt: records.map(\.fetchedAt).min() ?? now
      ).lists
    }
  }

  private static let lotlBytes = Data("list of the lists".utf8)
  private static let nationalBytes = Data("national list".utf8)
  private static let nationalLocation = "https://trusted-list.example/fi.xml"
  private static let fetchedAt = Date(timeIntervalSince1970: 1_780_272_000)
  private static let nextUpdate = Self.fetchedAt.addingTimeInterval(TrustedListStore.maximumAge)

  /// A fresh cache directory.
  private static func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "TrustedListHuskCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  /// A network serving the lists.
  private static func served() -> TrustedListFakeNetwork {
    TrustedListFakeNetwork(
      served: [
        TrustedLists.listOfTheListsLocation: Self.lotlBytes,
        Self.nationalLocation: Self.nationalBytes,
      ],
      offline: false)
  }

  private static func dependencies(
    network: TrustedListFakeNetwork,
    reader: HuskReader,
    directory: URL,
    now: Date
  ) -> TrustedListStore.Dependencies {
    TrustedListStore.Dependencies(
      fetch: { location in try network.fetch(location) },
      directory: directory,
      reader: reader,
      now: { now }
    )
  }
  /// A fetch that reads no national list fails and writes no cache:
  /// a husk must never pose as fresh lists.
  @Test
  internal func fetchWithNoNationalListFailsAndWritesNothing() async throws {
    let directory = try Self.directory()
    let network = Self.served()
    let reader = HuskReader(
      lotlBytes: Self.lotlBytes, nationalLocation: Self.nationalLocation,
      nextUpdate: Self.nextUpdate, now: Self.fetchedAt)
    let store = TrustedListStore(
      dependencies: Self.dependencies(
        network: network, reader: reader, directory: directory, now: Self.fetchedAt))
    await store.refreshNow()
    #expect(store.anchors == nil)
    #expect(store.lastRefreshFailure == .unavailable)
    #expect(
      !FileManager.default.fileExists(
        atPath: directory.appending(path: TrustedListStore.indexFileName).path))
  }

  /// Stored anchors with nothing in them are fetched again: an
  /// emptied cache heals on next use instead of bricking verification.
  @Test
  internal func emptyStoredAnchorsAreFetchedAgain() async throws {
    let directory = try Self.directory()
    let reader = HuskReader(
      lotlBytes: Self.lotlBytes, nationalLocation: Self.nationalLocation,
      nextUpdate: Self.nextUpdate, now: Self.fetchedAt)
    TrustedListStore.store(
      [
        TrustedLists.CachedList(
          location: TrustedLists.listOfTheListsLocation, fetchedAt: Self.fetchedAt,
          nextUpdate: Self.nextUpdate, bytes: Self.lotlBytes)
      ],
      in: directory)
    let network = Self.served()
    let store = TrustedListStore(
      dependencies: Self.dependencies(
        network: network, reader: reader, directory: directory, now: Self.fetchedAt))
    await store.refreshIfNeeded()
    #expect(!network.fetches.isEmpty, "empty anchors are fetched again")
  }
}
