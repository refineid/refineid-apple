// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import CardCore
@testable import RefineIDTestHost

/// A reader that hands out synthetic lists and counts its calls.
internal final class TrustedListFakeReader: TrustedListReader, @unchecked Sendable {
  /// The bytes the list of the lists must have.
  private let listOfTheListsBytes: Data

  /// The bytes the national list must have.
  private let nationalBytes: Data

  /// The next update every list states.
  private let nextUpdate: Date?

  /// How many times the cache was read back.
  internal private(set) var cacheReads = 0

  internal init(listOfTheListsBytes: Data, nationalBytes: Data, nextUpdate: Date?) {
    self.listOfTheListsBytes = listOfTheListsBytes
    self.nationalBytes = nationalBytes
    self.nextUpdate = nextUpdate
  }

  internal func listOfTheLists(_ bytes: Data) throws -> TrustedList {
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

  internal func lists(
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

  internal func cached(_ records: [TrustedLists.CachedList]) throws -> TrustedLists {
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
