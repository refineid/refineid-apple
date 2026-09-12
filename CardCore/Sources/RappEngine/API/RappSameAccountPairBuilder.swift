// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// Builds deterministic `RappPairRecord` representations for devices sharing the same Apple ID.
///
/// Both devices deterministically derive the exact same `pairIdentifier`, `rendezvousToken`,
/// and `grantsHash` from their mutual static public keys and shared domain separation prefixes.
public enum RappSameAccountPairBuilder {
  // MARK: Static Constants

  private static let pairDomain = Data("RefineID:SameAccountPair:v1".utf8)
  private static let rendezvousDomain = Data("RefineID:SameAccountRendezvous:v1".utf8)
  private static let defaultProfiles = [
    ProfileName.cardStatus,
    ProfileName.authentication,
    ProfileName.documentSigning,
  ]
  private static let millisecondsPerSecond: Double = 1_000.0

  // MARK: Static Functions

  /// Derives the unique 16-byte pair identifier from two public keys.
  public static func derivePairIdentifier(publicKeyA: Data, publicKeyB: Data) -> Data {
    let (minKey, maxKey) = sortKeys(publicKeyA, publicKeyB)
    let digest = SHA256.hash(data: pairDomain + minKey + maxKey)
    return Data(digest.prefix(PairRecordSize.pairIdentifier))
  }

  /// Derives the 16-byte rendezvous token from two public keys.
  public static func deriveRendezvousToken(publicKeyA: Data, publicKeyB: Data) -> Data {
    let (minKey, maxKey) = sortKeys(publicKeyA, publicKeyB)
    let digest = SHA256.hash(data: rendezvousDomain + minKey + maxKey)
    return Data(digest.prefix(PairRecordSize.rendezvousToken))
  }

  /// Builds a complete `RappPairRecord` for a same-account peer using the current timestamp.
  public static func makePairRecord(
    localStaticPrivate: Data,
    localStaticPublic: Data,
    localRole: RappEndpointRole,
    remotePublicKey: Data
  ) throws -> RappPairRecord {
    try makePairRecord(
      localStaticPrivate: localStaticPrivate,
      localStaticPublic: localStaticPublic,
      localRole: localRole,
      remotePublicKey: remotePublicKey,
      createdAtMilliseconds: UInt64(Date().timeIntervalSince1970 * millisecondsPerSecond)
    )
  }

  /// Builds a complete `RappPairRecord` for a same-account peer with a specific creation timestamp.
  public static func makePairRecord(
    localStaticPrivate: Data,
    localStaticPublic: Data,
    localRole: RappEndpointRole,
    remotePublicKey: Data,
    createdAtMilliseconds: UInt64
  ) throws -> RappPairRecord {
    let pairID = derivePairIdentifier(
      publicKeyA: localStaticPublic,
      publicKeyB: remotePublicKey
    )
    let rendezvousToken = deriveRendezvousToken(
      publicKeyA: localStaticPublic,
      publicKeyB: remotePublicKey
    )
    let grantsHash: Data
    do {
      grantsHash = try RappHashes.grantsHash(profiles: defaultProfiles.map(\.rawValue))
    } catch {
      throw RappBindingError.InvalidInput
    }
    let transport = PairTransportBinding(
      profile: "stream",
      candidateIdentifier: "stream-tcp",
      parameters: [:]
    )

    let role: EndpointRole = (localRole == .requester) ? .requester : .proxy
    let rawRecord: PairRecord
    do {
      rawRecord = try PairRecord(
        pairIdentifier: pairID,
        rendezvousToken: rendezvousToken,
        role: role,
        localStaticPrivate: localStaticPrivate,
        localStaticPublic: localStaticPublic,
        remoteStaticPublic: remotePublicKey,
        grantsHash: grantsHash,
        profiles: defaultProfiles,
        transport: transport,
        createdAtMilliseconds: createdAtMilliseconds
      )
    } catch {
      throw RappBindingError.InvalidInput
    }

    return RappPairRecord(record: rawRecord)
  }

  private static func sortKeys(_ firstKey: Data, _ secondKey: Data) -> (Data, Data) {
    guard !firstKey.lexicographicallyPrecedes(secondKey) else {
      return (firstKey, secondKey)
    }
    return (secondKey, firstKey)
  }
}
