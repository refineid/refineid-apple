// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// Reads trusted lists for `TrustedListStore`: the live reader verifies
/// them under the shipped signers, a test's reader supplies lists.
internal protocol TrustedListReader: Sendable {
  /// The list of the lists in `bytes`, verified.
  func listOfTheLists(_ bytes: Data) throws -> TrustedList

  /// The list of the lists and the national lists `national` supplies,
  /// verified.
  func lists(
    listOfTheLists bytes: Data,
    national: (String) -> Data?,
    fetchedAt: Date
  ) throws -> TrustedLists.Reading

  /// The lists the cache records hold, verified again.
  func cached(_ records: [TrustedLists.CachedList]) throws -> TrustedLists
}
