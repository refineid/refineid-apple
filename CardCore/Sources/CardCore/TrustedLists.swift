// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The list of the lists and the national lists it points at, each
/// verified (ETSI TS 119 612).
///
/// `read` applies `TrustedList.read` twice: to the list of the lists
/// under the Commission certificates the software ships
/// (`EuListOfTheListsSigners`), then to each national list under the
/// certificates the list of the lists carries in its pointer. Pointers
/// are followed one level: a national list's own pointers are read but
/// never fetched. `TrustAnchors(trustedLists:)` turns the qualified
/// certificate-issuing and time-stamping services of the national lists
/// into anchors.
///
/// Fetching and caching are the shell's: it fetches the list of the
/// lists from `listOfTheListsLocation`, reads it with `TrustedList.read`
/// to learn the pointers, fetches the national lists they name, and
/// hands every list here. Beside the lists, `read` returns one
/// `CachedList` per list for the shell to store; `fromCache` reads the
/// stored records back, verifying every signature again. Nothing here
/// touches the network or a file.
public struct TrustedLists: Sendable {
  /// One fetched list as the shell stores it: the bytes, when they were
  /// fetched and when the list says it will be superseded.
  public struct CachedList: Sendable, Equatable {
    /// Where the bytes were fetched from.
    public let location: String

    /// When they were fetched.
    public let fetchedAt: Date

    /// The list's next update; nil for a closed list.
    public let nextUpdate: Date?

    /// The bytes, as fetched, for `fromCache` to read and verify again.
    public let bytes: Data

    /// A record the shell reconstructs from its store.
    public init(location: String, fetchedAt: Date, nextUpdate: Date?, bytes: Data) {
      self.location = location
      self.fetchedAt = fetchedAt
      self.nextUpdate = nextUpdate
      self.bytes = bytes
    }
  }

  /// Why a national list the list of the lists points at yielded no
  /// anchors.
  public enum ListFailure: Error, Sendable, Equatable {
    /// The pointer's location is not a URL the shell fetches.
    case noLocation

    /// The shell supplied no bytes for the location.
    case notFetched

    /// The list read is not a member state list.
    case notNational

    /// The bytes did not read as a list signed by a pointer signer.
    case unreadable(TrustedListError)
  }

  /// One national list the list of the lists points at, read or not.
  public struct NationalList: Sendable {
    /// The pointer's territory.
    public let territory: String

    /// The pointer's location.
    public let location: String?

    /// The list, or why there is none.
    public let outcome: Result<TrustedList, ListFailure>
  }

  /// What `read` yields: the lists and the records to store.
  public struct Reading: Sendable {
    /// The lists.
    public let lists: TrustedLists

    /// One record per list that read.
    public let cache: [CachedList]
  }

  /// Where the European Commission publishes the List of Trusted Lists
  /// (its `DistributionPoints` entry, and the location notified in the
  /// Official Journal).
  public static let listOfTheListsLocation = "https://ec.europa.eu/tools/lotl/eu-lotl.xml"

  /// The list of the lists.
  public let listOfTheLists: TrustedList

  /// One entry per pointer to a machine-processable national list, in
  /// the order the list of the lists carries them.
  public let national: [NationalList]

  /// When the lists were fetched.
  public let fetchedAt: Date

  /// The earliest next update among the list of the lists and the
  /// national lists that read.
  ///
  /// The instant from which the anchors taken from them come from a
  /// stale list; nil when every list is closed.
  public var validUntil: Date? {
    readable.compactMap(\.nextUpdate).min()
  }

  /// The list of the lists and every national list that read.
  private var readable: [TrustedList] {
    [listOfTheLists] + national.compactMap { list in try? list.outcome.get() }
  }

  /// Reads the list of the lists from `listOfTheLists` under
  /// `signers`, then each national list it points at from the bytes
  /// `national` returns for the pointer's location, under the pointer's
  /// signers.
  ///
  /// Pointers to a human-readable form, to the list of the lists itself
  /// or to a list type the reader does not read are not followed; a
  /// national list's own pointers are never followed. A national list
  /// that does not read is an entry with its `ListFailure`, not an
  /// error.
  ///
  /// Throws `TrustedListError` when the list of the lists does not
  /// read, or is not of the list-of-the-lists type.
  public static func read(
    listOfTheLists bytes: Data,
    signers: [Data],
    national: (String) -> Data?,
    fetchedAt: Date
  ) throws -> Reading {
    let lotl = try TrustedList.read(bytes, signers: signers)
    guard lotl.kind == .euListOfTheLists else {
      throw TrustedListError.notListOfTheLists
    }
    var cache = [
      CachedList(
        location: Self.listOfTheListsLocation, fetchedAt: fetchedAt,
        nextUpdate: lotl.nextUpdate, bytes: bytes)
    ]
    var lists: [NationalList] = []
    for pointer in lotl.pointers where pointer.namesNationalList {
      let listBytes = pointer.location.flatMap(national)
      let outcome = Self.nationalList(at: pointer, bytes: listBytes)
      if let location = pointer.location, let listBytes, case .success(let list) = outcome {
        cache.append(
          CachedList(
            location: location, fetchedAt: fetchedAt, nextUpdate: list.nextUpdate,
            bytes: listBytes))
      }
      lists.append(
        NationalList(territory: pointer.territory, location: pointer.location, outcome: outcome))
    }
    return Reading(
      lists: Self(listOfTheLists: lotl, national: lists, fetchedAt: fetchedAt),
      cache: cache
    )
  }

  /// Reads the lists back from the records a shell stored.
  ///
  /// The record at `listOfTheListsLocation` is the list of the lists,
  /// read under `signers`, the others serve its pointers by location.
  /// Every signature is verified again; the lists count as fetched at
  /// the oldest record's time.
  ///
  /// Throws `TrustedListError.notFetched` without a record for the list
  /// of the lists; otherwise as `read`.
  public static func fromCache(_ records: [CachedList], signers: [Data]) throws -> Self {
    guard let lotl = records.first(where: { $0.location == Self.listOfTheListsLocation }) else {
      throw TrustedListError.notFetched
    }
    let oldest = records.map(\.fetchedAt).min() ?? lotl.fetchedAt
    return try Self.read(
      listOfTheLists: lotl.bytes,
      signers: signers,
      national: { location in records.first { $0.location == location }?.bytes },
      fetchedAt: oldest
    ).lists
  }

  /// The national list `pointer` names, read under the pointer's
  /// signers from `bytes`, what arrived for its location.
  private static func nationalList(
    at pointer: TrustedListPointer,
    bytes: Data?
  ) -> Result<TrustedList, ListFailure> {
    guard pointer.location != nil else { return .failure(.noLocation) }
    guard let bytes else { return .failure(.notFetched) }
    do {
      let list = try TrustedList.read(bytes, signers: pointer.signers)
      guard list.kind == .euGeneric else { return .failure(.notNational) }
      return .success(list)
    } catch let error as TrustedListError {
      return .failure(.unreadable(error))
    } catch {
      return .failure(.unreadable(.malformed("unreadable")))
    }
  }

  /// Whether any list the anchors come from is past its next update at
  /// `now`.
  public func isStale(at now: Date) -> Bool {
    readable.contains { list in list.isStale(at: now) }
  }
}
