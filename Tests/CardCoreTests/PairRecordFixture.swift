// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
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
    /// The name a requester's record gives its phone.
    internal static let phoneName = "iOS - example-phone"
    /// The name a custodian's record gives its computer.
    internal static let computerName = "macOS - example-host"

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
      try makePairRecord(
        local: (localStaticPrivate, localStaticPublic), localRole: localRole,
        remotePublicKey: remotePublicKey, createdAtMilliseconds: createdAtMilliseconds,
        storageConfirmed: true)
    }

    /// A record for the peer `remotePublicKey` whose storage the peer never
    /// confirmed.
    internal static func makeUnconfirmedPairRecord(
      localStaticPrivate: Data,
      localStaticPublic: Data,
      localRole: RappEndpointRole,
      remotePublicKey: Data
    ) throws -> RappPairRecord {
      try makePairRecord(
        local: (localStaticPrivate, localStaticPublic), localRole: localRole,
        remotePublicKey: remotePublicKey,
        createdAtMilliseconds: UInt64(Date().timeIntervalSince1970 * Self.millisecondsPerSecond),
        storageConfirmed: false)
    }

    private static func makePairRecord(
      local: (staticPrivate: Data, staticPublic: Data),
      localRole: RappEndpointRole,
      remotePublicKey: Data,
      createdAtMilliseconds: UInt64,
      storageConfirmed: Bool
    ) throws -> RappPairRecord {
      let localStaticPrivate = local.staticPrivate
      let localStaticPublic = local.staticPublic
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
        peerDisplayName: localRole == .requester ? Self.phoneName : Self.computerName,
        storageConfirmed: storageConfirmed
      )
      return RappPairRecord(record: record)
    }
  }
#endif
