// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore
@testable import RefineIDTestHost

/// The trusted-list store: fetching, caching, reading the cache back,
/// and when it fetches again.
@MainActor
@Suite
internal struct TrustedListStoreTests {
  /// A reader that hands out synthetic lists and counts its calls.
  private final class FakeReader: TrustedListReader, @unchecked Sendable {
    /// The bytes the list of the lists must have.
    private let listOfTheListsBytes: Data

    /// The bytes the national list must have.
    private let nationalBytes: Data

    /// The next update every list states.
    private let nextUpdate: Date?

    /// How many times the cache was read back.
    private(set) var cacheReads = 0

    init(listOfTheListsBytes: Data, nationalBytes: Data, nextUpdate: Date?) {
      self.listOfTheListsBytes = listOfTheListsBytes
      self.nationalBytes = nationalBytes
      self.nextUpdate = nextUpdate
    }

    func listOfTheLists(_ bytes: Data) throws -> TrustedList {
      guard bytes == listOfTheListsBytes else { throw TrustedListError.signatureInvalid }
      return TrustedListStoreTests.list(
        .euListOfTheLists, nextUpdate: nextUpdate,
        pointers: [
          TrustedListPointer(
            location: TrustedListStoreTests.nationalLocation,
            territory: TrustedListStoreTests.territory, kind: .euGeneric, format: .xml,
            signers: [], unreadableSigners: 0)
        ])
    }

    func lists(
      listOfTheLists bytes: Data,
      national: (String) -> Data?,
      fetchedAt: Date
    ) throws -> TrustedLists.Reading {
      let lotl = try listOfTheLists(bytes)
      guard national(TrustedListStoreTests.nationalLocation) == nationalBytes else {
        throw TrustedListError.notFetched
      }
      let lists = TrustedLists(
        listOfTheLists: lotl,
        national: [
          TrustedLists.NationalList(
            territory: TrustedListStoreTests.territory,
            location: TrustedListStoreTests.nationalLocation,
            outcome: .success(
              TrustedListStoreTests.list(.euGeneric, nextUpdate: nextUpdate, pointers: [])))
        ],
        fetchedAt: fetchedAt)
      return TrustedLists.Reading(
        lists: lists,
        cache: [
          TrustedLists.CachedList(
            location: TrustedLists.listOfTheListsLocation, fetchedAt: fetchedAt,
            nextUpdate: nextUpdate, bytes: bytes),
          TrustedLists.CachedList(
            location: TrustedListStoreTests.nationalLocation, fetchedAt: fetchedAt,
            nextUpdate: nextUpdate, bytes: nationalBytes),
        ])
    }

    func cached(_ records: [TrustedLists.CachedList]) throws -> TrustedLists {
      cacheReads += 1
      guard let lotl = records.first(where: { $0.location == TrustedLists.listOfTheListsLocation })
      else {
        throw TrustedListError.notFetched
      }
      return try lists(
        listOfTheLists: lotl.bytes,
        national: { location in records.first { $0.location == location }?.bytes },
        fetchedAt: records.map(\.fetchedAt).min() ?? lotl.fetchedAt
      ).lists
    }
  }

  /// Serves bytes by location and counts the fetches.
  private final class FakeNetwork: @unchecked Sendable {
    private let served: [String: Data]
    private(set) var fetches: [String] = []

    init(served: [String: Data]) {
      self.served = served
    }

    func fetch(_ location: String) throws -> Data {
      fetches.append(location)
      guard let bytes = served[location] else { throw TrustedListError.notFetched }
      return bytes
    }
  }

  nonisolated private static let territory = "FI"
  nonisolated private static let nationalLocation = "https://trusted-list.example/fi.xml"
  private static let lotlBytes = Data("list of the lists".utf8)
  private static let nationalBytes = Data("national list".utf8)
  nonisolated private static let fetchedAt = Date(timeIntervalSince1970: 1_780_272_000)
  private static let nextUpdate = Self.fetchedAt.addingTimeInterval(TrustedListStore.maximumAge)

  /// The fetches one refresh makes: the list of the lists and the one
  /// national list.
  private static let oneRound = 2

  /// A list of `kind` with no services.
  nonisolated private static func list(
    _ kind: TrustedList.Kind,
    nextUpdate: Date?,
    pointers: [TrustedListPointer]
  ) -> TrustedList {
    TrustedList(
      kind: kind, territory: Self.territory, operatorName: "Operator", issuedAt: Self.fetchedAt,
      nextUpdate: nextUpdate, pointers: pointers, services: [], signer: Data())
  }

  /// A fresh cache directory.
  private static func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "TrustedListStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private static func dependencies(
    network: FakeNetwork,
    reader: FakeReader,
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

  private static func served() -> FakeNetwork {
    FakeNetwork(served: [
      TrustedLists.listOfTheListsLocation: Self.lotlBytes,
      Self.nationalLocation: Self.nationalBytes,
    ])
  }

  @Test
  internal func withoutACacheTheFirstUseFetchesAndStores() async throws {
    let directory = try Self.directory()
    let network = Self.served()
    let reader = FakeReader(
      listOfTheListsBytes: Self.lotlBytes, nationalBytes: Self.nationalBytes,
      nextUpdate: Self.nextUpdate)
    let store = TrustedListStore(
      dependencies: Self.dependencies(
        network: network, reader: reader, directory: directory, now: Self.fetchedAt))
    #expect(await store.loadedAnchors() == nil)
    await store.refreshIfNeeded()
    let anchors = try #require(store.anchors)
    #expect(anchors.fetchedAt == Self.fetchedAt)
    #expect(anchors.listsValidUntil == Self.nextUpdate)
    #expect(!store.lastRefreshFailed)
    #expect(network.fetches == [TrustedLists.listOfTheListsLocation, Self.nationalLocation])
    let index = directory.appending(path: TrustedListStore.indexFileName)
    let records = try JSONDecoder().decode(
      [TrustedListCacheRecord].self, from: Data(contentsOf: index))
    #expect(
      records.map(\.location) == [TrustedLists.listOfTheListsLocation, Self.nationalLocation])
    for record in records {
      #expect(record.fetchedAt == Self.fetchedAt)
      #expect(FileManager.default.fileExists(atPath: directory.appending(path: record.file).path))
    }
  }

  @Test
  internal func theCacheServesAFreshStoreWithoutTheNetwork() async throws {
    let directory = try Self.directory()
    let reader = FakeReader(
      listOfTheListsBytes: Self.lotlBytes, nationalBytes: Self.nationalBytes,
      nextUpdate: Self.nextUpdate)
    let first = TrustedListStore(
      dependencies: Self.dependencies(
        network: Self.served(), reader: reader, directory: directory, now: Self.fetchedAt))
    await first.refreshIfNeeded()

    let offline = FakeNetwork(served: [:])
    let second = TrustedListStore(
      dependencies: Self.dependencies(
        network: offline, reader: reader, directory: directory,
        now: Self.fetchedAt.addingTimeInterval(1)))
    await second.refreshIfNeeded()
    #expect(second.anchors?.fetchedAt == Self.fetchedAt)
    #expect(offline.fetches.isEmpty)
    #expect(reader.cacheReads == 1)
    #expect(!second.lastRefreshFailed)
  }

  @Test
  internal func aStaleOrAgedCacheIsFetchedAgainAndAFailedFetchKeepsIt() async throws {
    let directory = try Self.directory()
    let reader = FakeReader(
      listOfTheListsBytes: Self.lotlBytes, nationalBytes: Self.nationalBytes,
      nextUpdate: Self.nextUpdate)
    let first = TrustedListStore(
      dependencies: Self.dependencies(
        network: Self.served(), reader: reader, directory: directory, now: Self.fetchedAt))
    await first.refreshIfNeeded()

    let offline = FakeNetwork(served: [:])
    let later = Self.nextUpdate.addingTimeInterval(1)
    let aged = TrustedListStore(
      dependencies: Self.dependencies(
        network: offline, reader: reader, directory: directory, now: later))
    await aged.refreshIfNeeded()
    #expect(offline.fetches == [TrustedLists.listOfTheListsLocation])
    #expect(aged.lastRefreshFailed)
    #expect(aged.anchors?.fetchedAt == Self.fetchedAt, "the cache stays when the fetch fails")
    #expect(aged.anchors?.isStale(at: later) == true)

    let online = Self.served()
    let refreshed = TrustedListStore(
      dependencies: Self.dependencies(
        network: online, reader: reader, directory: directory, now: later))
    await refreshed.refreshIfNeeded()
    #expect(refreshed.anchors?.fetchedAt == later)
    #expect(!refreshed.lastRefreshFailed)
  }

  @Test
  internal func anExplicitRefreshFetchesEvenWhenFresh() async throws {
    let directory = try Self.directory()
    let network = Self.served()
    let reader = FakeReader(
      listOfTheListsBytes: Self.lotlBytes, nationalBytes: Self.nationalBytes,
      nextUpdate: Self.nextUpdate)
    let store = TrustedListStore(
      dependencies: Self.dependencies(
        network: network, reader: reader, directory: directory, now: Self.fetchedAt))
    await store.refreshIfNeeded()
    await store.refreshIfNeeded()
    #expect(network.fetches.count == Self.oneRound)
    await store.refreshNow()
    #expect(network.fetches.count == Self.oneRound + Self.oneRound)
    #expect(!store.isRefreshing)
  }
}
