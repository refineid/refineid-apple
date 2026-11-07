// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// Fetches, caches and verifies the EU trusted lists (ETSI TS 119 612)
/// the document verifier takes its anchors from.
///
/// The list of the lists is fetched from its published location and
/// read under the six Official Journal certificates the software ships;
/// the national lists it points at are fetched and read under the
/// pointers' certificates. The raw bytes of every list that read are
/// kept with their fetch time in the app's own Application Support
/// container, so an offline start verifies from the cache, every
/// signature checked again. The lists are fetched again when nothing is
/// cached, when a cached list is past its `NextUpdate`, when the cache
/// is older than `maximumAge`, and when the holder asks.
///
/// Verification of a list, which parses megabytes of XML, runs off the
/// main actor; this object publishes the outcome.
@MainActor
internal final class TrustedListStore: ObservableObject {
  /// Reading, fetching, storage and the clock, injected for tests.
  internal struct Dependencies: Sendable {
    /// The cache directory's name.
    private static let directoryName = "TrustedLists"

    /// The app's network, cache directory, shipped signers and clock.
    internal static let live = Self(
      fetch: Self.liveFetch,
      directory: Self.liveDirectory,
      reader: ShippedSignerTrustedListReader(),
      now: Date.init
    )

    /// `TrustedLists/` in the app's Application Support directory.
    private static var liveDirectory: URL {
      let support =
        (try? FileManager.default.url(
          for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
          create: true))
        ?? FileManager.default.temporaryDirectory
      return support.appending(path: Self.directoryName, directoryHint: .isDirectory)
    }

    /// GETs one list by its location.
    internal let fetch: @Sendable (String) async throws -> Data

    /// Where the cache lives.
    internal let directory: URL

    /// Reads and verifies the lists.
    internal let reader: any TrustedListReader

    /// The current time.
    internal let now: @Sendable () -> Date

    /// Groups one environment.
    internal init(
      fetch: @escaping @Sendable (String) async throws -> Data,
      directory: URL,
      reader: any TrustedListReader,
      now: @escaping @Sendable () -> Date
    ) {
      self.fetch = fetch
      self.directory = directory
      self.reader = reader
      self.now = now
    }

    /// One list over the app's outbound network policy.
    private static func liveFetch(_ location: String) async throws -> Data {
      try await SigningNetwork.get(
        location, maximumBytes: TrustedList.maximumBytes, endpoint: .certificateMaterial)
    }
  }

  /// The app's one store.
  internal static let shared = TrustedListStore(dependencies: .live)

  /// How old a fetch may grow before the lists are fetched again
  /// although none is past its next update: seven days, in seconds.
  nonisolated internal static let maximumAge: TimeInterval = 604_800

  /// The anchors the lists yield, or nil while no list has been read.
  @Published internal private(set) var anchors: TrustAnchors?

  /// Whether a fetch is under way.
  @Published internal private(set) var isRefreshing = false

  /// Whether the last fetch failed to yield lists.
  @Published internal private(set) var lastRefreshFailed = false

  /// The dependencies.
  internal let dependencies: Dependencies

  /// The one cache load, started on first use.
  private var cacheLoad: Task<Void, Never>?

  /// The running refresh, if any.
  private var refresh: Task<Void, Never>?

  /// A store over `dependencies`.
  internal init(dependencies: Dependencies) {
    self.dependencies = dependencies
  }

  /// The anchors once the cache has been read and any first fetch under
  /// way has ended, nil when neither has yielded lists.
  internal func loadedAnchors() async -> TrustAnchors? {
    await loadCache()
    if anchors == nil {
      await refresh?.value
    }
    return anchors
  }

  /// Reads the cache once; later calls wait for that read.
  internal func loadCache() async {
    if cacheLoad == nil {
      let environment = dependencies
      cacheLoad = Task { [weak self] in
        let lists = await Task.detached(priority: .utility) {
          Self.cachedLists(environment)
        }.value
        guard let self, let lists else { return }
        anchors = TrustAnchors(trustedLists: lists)
      }
    }
    await cacheLoad?.value
  }

  /// Reads the cache, then fetches when nothing is cached, a list is
  /// past its next update, or the fetch is older than `maximumAge`.
  internal func refreshIfNeeded() async {
    await loadCache()
    let now = dependencies.now()
    let aged = anchors?.fetchedAt.map { fetched in
      now.timeIntervalSince(fetched) > Self.maximumAge
    }
    if anchors == nil || anchors?.isStale(at: now) == true || aged != false {
      await refreshNow()
    }
  }

  /// Fetches the lists again, as the holder asked.
  internal func refreshNow() async {
    if refresh == nil {
      isRefreshing = true
      let environment = dependencies
      refresh = Task { [weak self] in
        let fetched = await Self.fetchLists(environment)
        guard let self else { return }
        if let fetched {
          anchors = TrustAnchors(trustedLists: fetched)
        }
        lastRefreshFailed = fetched == nil
        isRefreshing = false
        refresh = nil
      }
    }
    await refresh?.value
  }
}
