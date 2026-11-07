// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// The live reader: `TrustedLists` under the six Official Journal
/// certificates the software ships.
internal struct ShippedSignerTrustedListReader: TrustedListReader {
  /// The certificates entitled to sign the list of the lists.
  private let signers = EuListOfTheListsSigners.certificates

  internal func listOfTheLists(_ bytes: Data) throws -> TrustedList {
    try TrustedList.read(bytes, signers: signers)
  }

  internal func lists(
    listOfTheLists bytes: Data,
    national: (String) -> Data?,
    fetchedAt: Date
  ) throws -> TrustedLists.Reading {
    try TrustedLists.read(
      listOfTheLists: bytes, signers: signers, national: national, fetchedAt: fetchedAt)
  }

  internal func cached(_ records: [TrustedLists.CachedList]) throws -> TrustedLists {
    try TrustedLists.fromCache(records, signers: signers)
  }
}
