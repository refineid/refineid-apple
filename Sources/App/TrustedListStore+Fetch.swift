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
  /// does not arrive or does not read, and unavailable when no
  /// national list reads: a husk must never pose as fresh lists.
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
    let nationalRead = reading.lists.national.contains { list in
      guard case .success = list.outcome else { return false }
      return true
    }
    guard nationalRead else {
      return .failure(.unavailable)
    }
    Self.store(reading.cache, in: dependencies.directory)
    return .success(reading.lists)
  }

  /// The bytes of each location that arrives, a few at a time.
  ///
  /// Every worker is added before the group is drained, and each one
  /// walks its own slice in order, so every add happens before the first
  /// await on the group. A worker the caller cancels stops without
  /// recording its stop as a fetch failure.
  nonisolated private static func fetchNational(
    _ locations: [String],
    _ dependencies: Dependencies
  ) async -> [String: Data] {
    guard !locations.isEmpty else { return [:] }
    let workerCount = min(Self.concurrentFetches, locations.count)
    var slices = Array(repeating: [String](), count: workerCount)
    for (offset, location) in locations.enumerated() {
      slices[offset % workerCount].append(location)
    }
    return await withTaskGroup(of: [String: Data].self) { group in
      for slice in slices {
        group.addTask {
          var fetched: [String: Data] = [:]
          for location in slice {
            if Task.isCancelled { break }
            do {
              fetched[location] = try await dependencies.fetch(location)
            } catch {
              guard !Task.isCancelled else { break }
              Self.reportFetchFailure(location, error)
            }
          }
          return fetched
        }
      }
      var fetched: [String: Data] = [:]
      for await slice in group {
        fetched.merge(slice) { first, _ in first }
      }
      return fetched
    }
  }

  /// Reports one fetch or read failure in a development build: what
  /// was being fetched and the cause, never a certificate.
  nonisolated private static func reportFetchFailure(_ what: String, _ error: any Error) {
    #if DEBUG
      DevErrorLog.report("trusted list \(what): \(DevErrorLog.reason(error))", source: .app)
    #endif
  }
}
