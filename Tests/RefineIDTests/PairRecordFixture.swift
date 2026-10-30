// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  import CryptoKit
  import Foundation
  @testable import RappEngine

  /// A stored pair record between two static keys, made without a pairing
  /// ceremony, for tests that need a pairing to exist.
  ///
  /// Both ends derive the same pair identifier from the two public keys.
  internal enum PairRecordFixture {
    private static let pairDomain = Data("RefineID:TestPair".utf8)
    private static let profiles = [
      ProfileName.cardStatus,
      ProfileName.authentication,
      ProfileName.documentSigning,
    ]
    private static let millisecondsPerSecond: Double = 1_000.0

    /// A record for the peer `remotePublicKey`, created now.
    internal static func makePairRecord(
      localStaticPrivate: Data,
      localStaticPublic: Data,
      localRole: RappEndpointRole,
      remotePublicKey: Data
    ) throws -> RappPairRecord {
      try Self.makePairRecord(
        localStaticPrivate: localStaticPrivate,
        localStaticPublic: localStaticPublic,
        localRole: localRole,
        remotePublicKey: remotePublicKey,
        createdAtMilliseconds: UInt64(Date().timeIntervalSince1970 * Self.millisecondsPerSecond)
      )
    }

    /// A record for the peer `remotePublicKey` with the given creation time.
    internal static func makePairRecord(
      localStaticPrivate: Data,
      localStaticPublic: Data,
      localRole: RappEndpointRole,
      remotePublicKey: Data,
      createdAtMilliseconds: UInt64
    ) throws -> RappPairRecord {
      let ordered = [localStaticPublic, remotePublicKey].sorted { first, second in
        first.lexicographicallyPrecedes(second)
      }
      let digest = SHA256.hash(data: Self.pairDomain + ordered[0] + ordered[1])
      let record = try PairRecord(
        pairIdentifier: Data(digest.prefix(PairRecordSize.pairIdentifier)),
        role: localRole == .requester ? .requester : .proxy,
        localStaticPrivate: localStaticPrivate,
        localStaticPublic: localStaticPublic,
        remoteStaticPublic: remotePublicKey,
        grantsHash: try RappHashes.grantsHash(profiles: Self.profiles.map(\.rawValue)),
        profiles: Self.profiles,
        transport: PairTransportBinding(
          profile: "stream",
          candidateIdentifier: "stream-tcp",
          parameters: [:]
        ),
        createdAtMilliseconds: createdAtMilliseconds,
        storageConfirmed: true
      )
      return RappPairRecord(record: record)
    }
  }
#endif
