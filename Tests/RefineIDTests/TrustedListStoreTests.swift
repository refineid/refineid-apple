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
  nonisolated internal static let territory = "FI"
  nonisolated internal static let nationalLocation = "https://trusted-list.example/fi.xml"
  private static let lotlBytes = Data("list of the lists".utf8)
  private static let nationalBytes = Data("national list".utf8)
  nonisolated private static let fetchedAt = Date(timeIntervalSince1970: 1_780_272_000)
  private static let nextUpdate = Self.fetchedAt.addingTimeInterval(TrustedListStore.maximumAge)

  /// The name of a document a test verifies.
  private static let documentName = "document.pdf"

  /// A document that is neither a PDF nor a container.
  private static let unsignedNote = Data("An unsigned note.".utf8)

  /// The fetches one refresh makes: the list of the lists and the one
  /// national list.
  private static let oneRound = 2

  /// A reader of the served lists.
  private static func reader() -> TrustedListFakeReader {
    TrustedListFakeReader(
      listOfTheListsBytes: Self.lotlBytes, nationalBytes: Self.nationalBytes,
      nextUpdate: Self.nextUpdate)
  }

  /// A list of `kind` with no services.
  nonisolated internal static func list(
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
    network: TrustedListFakeNetwork,
    reader: TrustedListFakeReader,
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

  private static func served() -> TrustedListFakeNetwork {
    TrustedListFakeNetwork(
      served: [
        TrustedLists.listOfTheListsLocation: Self.lotlBytes,
        Self.nationalLocation: Self.nationalBytes,
      ],
      offline: false)
  }

  @Test
  internal func withoutACacheTheFirstUseFetchesAndStores() async throws {
    let directory = try Self.directory()
    let network = Self.served()
    let reader = TrustedListFakeReader(
      listOfTheListsBytes: Self.lotlBytes, nationalBytes: Self.nationalBytes,
      nextUpdate: Self.nextUpdate)
    let store = TrustedListStore(
      dependencies: Self.dependencies(
        network: network, reader: reader, directory: directory, now: Self.fetchedAt))
    await store.loadCache()
    #expect(store.anchors == nil)
    await store.refreshIfNeeded()
    let anchors = try #require(store.anchors)
    #expect(anchors.fetchedAt == Self.fetchedAt)
    #expect(anchors.listsValidUntil == Self.nextUpdate)
    #expect(store.lastRefreshFailure == nil)
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
    let reader = TrustedListFakeReader(
      listOfTheListsBytes: Self.lotlBytes, nationalBytes: Self.nationalBytes,
      nextUpdate: Self.nextUpdate)
    let first = TrustedListStore(
      dependencies: Self.dependencies(
        network: Self.served(), reader: reader, directory: directory, now: Self.fetchedAt))
    await first.refreshIfNeeded()

    let offline = TrustedListFakeNetwork(served: [:], offline: false)
    let second = TrustedListStore(
      dependencies: Self.dependencies(
        network: offline, reader: reader, directory: directory,
        now: Self.fetchedAt.addingTimeInterval(1)))
    await second.refreshIfNeeded()
    #expect(second.anchors?.fetchedAt == Self.fetchedAt)
    #expect(offline.fetches.isEmpty)
    #expect(reader.cacheReads == 1)
    #expect(second.lastRefreshFailure == nil)
  }

  @Test
  internal func aStaleOrAgedCacheIsFetchedAgainAndAFailedFetchKeepsIt() async throws {
    let directory = try Self.directory()
    let reader = TrustedListFakeReader(
      listOfTheListsBytes: Self.lotlBytes, nationalBytes: Self.nationalBytes,
      nextUpdate: Self.nextUpdate)
    let first = TrustedListStore(
      dependencies: Self.dependencies(
        network: Self.served(), reader: reader, directory: directory, now: Self.fetchedAt))
    await first.refreshIfNeeded()

    let offline = TrustedListFakeNetwork(served: [:], offline: false)
    let later = Self.nextUpdate.addingTimeInterval(1)
    let aged = TrustedListStore(
      dependencies: Self.dependencies(
        network: offline, reader: reader, directory: directory, now: later))
    await aged.refreshIfNeeded()
    #expect(offline.fetches == [TrustedLists.listOfTheListsLocation])
    #expect(aged.lastRefreshFailure == .unavailable)
    #expect(aged.anchors?.fetchedAt == Self.fetchedAt, "the cache stays when the fetch fails")
    #expect(aged.anchors?.isStale(at: later) == true)

    let online = Self.served()
    let refreshed = TrustedListStore(
      dependencies: Self.dependencies(
        network: online, reader: reader, directory: directory, now: later))
    await refreshed.refreshIfNeeded()
    #expect(refreshed.anchors?.fetchedAt == later)
    #expect(refreshed.lastRefreshFailure == nil)
  }

  @Test
  internal func anExplicitRefreshFetchesEvenWhenFresh() async throws {
    let directory = try Self.directory()
    let network = Self.served()
    let reader = TrustedListFakeReader(
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

  /// With nothing cached and no connection, a signed document is told
  /// the device is offline, and so is the trusted-lists row.
  @Test
  internal func offlineWithoutACacheSaysOffline() async throws {
    let offline = TrustedListFakeNetwork(served: [:], offline: true)
    let store = TrustedListStore(
      dependencies: Self.dependencies(
        network: offline, reader: Self.reader(), directory: try Self.directory(),
        now: Self.fetchedAt))

    #expect(await store.verificationAnchors() == .failure(.offline))
    #expect(store.lastRefreshFailure == .offline)
    #expect(store.anchors == nil)
    #expect(offline.fetches == [TrustedLists.listOfTheListsLocation])

    let model = VerifyDocumentModel(
      dependencies: VerifyDocumentModel.Dependencies(
        anchors: { await store.verificationAnchors() },
        verify: { _, _ in VerifyDocumentModelFixture.documentReport },
        liveStatus: { _ in nil },
        now: { Self.fetchedAt }))
    model.verify(document: Self.lotlBytes, name: Self.documentName)
    await model.verification?.value
    guard case .failed(let message) = model.phase else {
      Issue.record("The verification did not fail")
      return
    }
    #expect(message == VerifyDocumentModel.offlineWithoutTrustedListsMessage)
  }

  /// Offline without a cache, a document without signatures still says
  /// so: that needs no trusted list.
  @Test
  internal func offlineWithoutACacheAnUnsignedDocumentSaysUnsigned() async throws {
    let store = TrustedListStore(
      dependencies: Self.dependencies(
        network: TrustedListFakeNetwork(served: [:], offline: true), reader: Self.reader(),
        directory: try Self.directory(), now: Self.fetchedAt))
    let model = VerifyDocumentModel(
      dependencies: VerifyDocumentModel.Dependencies(
        anchors: { await store.verificationAnchors() },
        verify: { document, anchors in
          try DocumentVerification.verify(document: document, anchors: anchors)
        },
        liveStatus: { _ in nil },
        now: { Self.fetchedAt }))
    model.verify(document: Self.unsignedNote, name: Self.documentName)
    await model.verification?.value
    guard case .failed(let message) = model.phase else {
      Issue.record("The verification did not fail")
      return
    }
    #expect(message == VerifyDocumentModel.noSignaturesMessage)
  }

  /// Without a cache, a fetch that fails for another reason is not
  /// reported as offline.
  @Test
  internal func aFailedFetchWithoutACacheIsUnavailable() async throws {
    let store = TrustedListStore(
      dependencies: Self.dependencies(
        network: TrustedListFakeNetwork(served: [:], offline: false), reader: Self.reader(),
        directory: try Self.directory(), now: Self.fetchedAt))

    #expect(await store.verificationAnchors() == .failure(.unavailable))
  }

  /// After one online fetch, an offline device verifies from the cache
  /// at once, even when the cache has aged past its next update.
  @Test
  internal func afterOneFetchAnOfflineDeviceVerifiesFromTheCache() async throws {
    let directory = try Self.directory()
    let reader = Self.reader()
    let first = TrustedListStore(
      dependencies: Self.dependencies(
        network: Self.served(), reader: reader, directory: directory, now: Self.fetchedAt))
    #expect(try await first.verificationAnchors().get().fetchedAt == Self.fetchedAt)

    let offline = TrustedListFakeNetwork(served: [:], offline: true)
    let later = Self.nextUpdate.addingTimeInterval(1)
    let second = TrustedListStore(
      dependencies: Self.dependencies(
        network: offline, reader: reader, directory: directory, now: later))
    let anchors = try await second.verificationAnchors().get()
    #expect(anchors.fetchedAt == Self.fetchedAt)
    #expect(offline.fetches.isEmpty, "verification does not wait for the network")

    await second.refreshIfNeeded()
    #expect(second.lastRefreshFailure == .offline)
    #expect(second.anchors?.fetchedAt == Self.fetchedAt, "the cache stays when offline")
  }
}
