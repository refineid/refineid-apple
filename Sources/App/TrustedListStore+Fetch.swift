// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// Fetching the list of the lists and the national lists it points at.
extension TrustedListStore {
  /// How many national lists are fetched at once.
  nonisolated private static let concurrentFetches = 4

  /// Fetches and reads every list, stores the ones that read, and
  /// returns them; offline when the list of the lists could not be
  /// fetched for want of a connection, unavailable when it otherwise
  /// does not arrive or does not read.
  nonisolated internal static func fetchLists(
    _ dependencies: Dependencies
  ) async -> Result<TrustedLists, RefreshFailure> {
    let fetchedAt = dependencies.now()
    let listOfTheLists: TrustedList
    let bytes: Data
    do {
      bytes = try await dependencies.fetch(TrustedLists.listOfTheListsLocation)
    } catch {
      Self.reportFetchFailure("list of the lists", error)
      return .failure(SigningNetwork.isOffline(error) ? .offline : .unavailable)
    }
    do {
      listOfTheLists = try dependencies.reader.listOfTheLists(bytes)
    } catch {
      Self.reportFetchFailure("list of the lists", error)
      return .failure(.unavailable)
    }
    let locations = listOfTheLists.pointers.filter(\.namesNationalList).compactMap(\.location)
    let national = await Self.fetchNational(locations, dependencies)
    let reading: TrustedLists.Reading
    do {
      reading = try await Task.detached(priority: .utility) {
        try dependencies.reader.lists(
          listOfTheLists: bytes, national: { location in national[location] },
          fetchedAt: fetchedAt)
      }.value
    } catch {
      Self.reportFetchFailure("lists", error)
      return .failure(.unavailable)
    }
    for list in reading.lists.national {
      if case .failure(let failure) = list.outcome, failure != .notFetched {
        Self.reportFetchFailure(list.territory, failure)
      }
    }
    Self.store(reading.cache, in: dependencies.directory)
    return .success(reading.lists)
  }

  /// The bytes of each location that arrives, a few at a time.
  nonisolated private static func fetchNational(
    _ locations: [String],
    _ dependencies: Dependencies
  ) async -> [String: Data] {
    var fetched: [String: Data] = [:]
    await withTaskGroup(of: (String, Data?).self) { group in
      var pending = locations[...]
      func startNext() {
        guard let location = pending.popFirst() else { return }
        group.addTask {
          do {
            return (location, try await dependencies.fetch(location))
          } catch {
            Self.reportFetchFailure(location, error)
            return (location, nil)
          }
        }
      }
      for _ in 0..<Self.concurrentFetches {
        startNext()
      }
      for await (location, bytes) in group {
        if let bytes { fetched[location] = bytes }
        startNext()
      }
    }
    return fetched
  }

  /// Reports one fetch or read failure in a development build: what
  /// was being fetched and the cause, never a certificate.
  nonisolated private static func reportFetchFailure(_ what: String, _ error: any Error) {
    #if DEBUG
      DevErrorLog.report("trusted list \(what): \(DevErrorLog.reason(error))", source: .app)
    #endif
  }
}
