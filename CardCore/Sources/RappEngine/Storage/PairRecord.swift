// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Storage-format version of a persisted pairing.
internal let pairRecordFormatVersion: UInt64 = 7

/// One durable pairing, as stored on this device only.
internal struct PairRecord: Equatable {
  /// Every key a stored record may carry, and must carry in full.
  private static let expectedKeys = [
    "format_version", "pair_id", "role", "local_static_private",
    "local_static_public", "remote_static_public", "grants_hash", "profiles", "transport_profile",
    "candidate_id", "transport_parameters", "created_at_ms", "storage_confirmed",
    "forgotten_at_ms", "last_session_at_ms",
  ]

  /// Days a forgotten record keeps its key for the `pairing_revoked` close
  /// (RAPP v26.10.22 §4.6 item 3).
  internal static let revocationNoticeDays: UInt64 = 30
  /// Days a pairing lives without an established session before it expires
  /// (RAPP v26.10.22 §4.6 item 5).
  internal static let pairingIdleExpiryDays: UInt64 = 30
  private static let millisecondsPerDay: UInt64 = 86_400_000
  /// How long a pairing lives without an established session.
  internal static let pairingIdleExpiryMilliseconds = pairingIdleExpiryDays * millisecondsPerDay

  internal let pairIdentifier: Data
  internal let role: EndpointRole
  internal let localStaticPrivate: Data
  internal let localStaticPublic: Data
  internal let remoteStaticPublic: Data
  internal let grantsHash: Data
  internal let profiles: [ProfileName]
  internal let transport: PairTransportBinding
  internal let createdAtMilliseconds: UInt64
  /// Whether both endpoints confirmed storing the pairing.
  ///
  /// A record stored before the peer's `pairing.stored` is unconfirmed
  /// (RAPP v26.10.22 §4.3 item 4): it opens no session, routes nothing,
  /// and is revoked when found at start-up.
  internal private(set) var storageConfirmed: Bool
  /// When the local user forgot the pairing, or it expired (§4.6 item 5),
  /// while no session was open, in milliseconds since the Unix epoch.
  ///
  /// A forgotten record serves nothing and keeps its key only to deliver the
  /// `pairing_revoked` close on the next session (§4.6 item 2).
  internal private(set) var forgottenAtMilliseconds: UInt64?
  /// The latest wall-clock time at which the pairing had an established
  /// session (§4.6 item 5).
  ///
  /// Milliseconds since the Unix epoch, nil while the pairing has had none.
  /// It only moves forward, and only
  /// ``sweep(nowMilliseconds:sessionEstablished:store:)`` records a session.
  internal private(set) var lastSessionAtMilliseconds: UInt64?

  internal init(
    pairIdentifier: Data,
    role: EndpointRole,
    localStaticPrivate: Data,
    localStaticPublic: Data,
    remoteStaticPublic: Data,
    grantsHash: Data,
    profiles: [ProfileName],
    transport: PairTransportBinding,
    createdAtMilliseconds: UInt64,
    storageConfirmed: Bool
  ) throws {
    guard pairIdentifier.count == PairRecordSize.pairIdentifier,
      grantsHash.count == PairRecordSize.grantsHash,
      localStaticPrivate.count == PairRecordSize.staticKey,
      localStaticPublic.count == PairRecordSize.staticKey,
      remoteStaticPublic.count == PairRecordSize.staticKey
    else { throw PairRecordError.invalidInput }
    guard !localStaticPrivate.allSatisfy({ $0 == 0 }),
      !localStaticPublic.allSatisfy({ $0 == 0 }),
      !remoteStaticPublic.allSatisfy({ $0 == 0 })
    else { throw PairRecordError.invalidInput }
    guard !profiles.isEmpty else { throw PairRecordError.invalidInput }
    guard !transport.profile.isEmpty, !transport.candidateIdentifier.isEmpty else {
      throw PairRecordError.invalidInput
    }
    self.pairIdentifier = pairIdentifier
    self.role = role
    self.localStaticPrivate = localStaticPrivate
    self.localStaticPublic = localStaticPublic
    self.remoteStaticPublic = remoteStaticPublic
    self.grantsHash = grantsHash
    self.profiles = profiles
    self.transport = transport
    self.createdAtMilliseconds = createdAtMilliseconds
    self.storageConfirmed = storageConfirmed
    self.forgottenAtMilliseconds = nil
    self.lastSessionAtMilliseconds = nil
  }

  internal static func decode(_ bytes: Data) throws -> Self {
    guard let decoded = try? decodeDeterministicCbor(bytes),
      case .map(var map) = decoded
    else { throw PairRecordError.invalidInput }
    guard map.keys.allSatisfy(expectedKeys.contains) else { throw PairRecordError.invalidInput }
    guard try takeUnsigned(&map, "format_version") == pairRecordFormatVersion else {
      throw PairRecordError.invalidInput
    }
    let decodedPairIdentifier = try takeBytes(&map, "pair_id")
    guard let decodedRole = EndpointRole(rawValue: try takeText(&map, "role")) else {
      throw PairRecordError.invalidInput
    }
    let decodedLocalStaticPrivate = try takeBytes(&map, "local_static_private")
    let decodedLocalStaticPublic = try takeBytes(&map, "local_static_public")
    let decodedRemoteStaticPublic = try takeBytes(&map, "remote_static_public")
    let decodedGrantsHash = try takeBytes(&map, "grants_hash")
    let decodedProfiles = try takeTextArray(&map, "profiles").map { name -> ProfileName in
      guard let profile = ProfileName(rawValue: name) else { throw PairRecordError.invalidInput }
      return profile
    }
    let decodedTransport = PairTransportBinding(
      profile: try takeText(&map, "transport_profile"),
      candidateIdentifier: try takeText(&map, "candidate_id"),
      parameters: try takeMap(&map, "transport_parameters")
    )
    let decodedCreatedAtMilliseconds = try takeUnsigned(&map, "created_at_ms")
    let decodedStorageConfirmed = try takeBoolean(&map, "storage_confirmed")
    let decodedForgottenAt = try takeOptionalUnsigned(&map, "forgotten_at_ms")
    let decodedLastSessionAt = try takeOptionalUnsigned(&map, "last_session_at_ms")
    guard map.isEmpty else { throw PairRecordError.invalidInput }
    // Only a confirmed record is kept as forgotten (§4.6 item 2).
    if decodedForgottenAt != nil, !decodedStorageConfirmed { throw PairRecordError.invalidInput }
    var record = try Self(
      pairIdentifier: decodedPairIdentifier,
      role: decodedRole,
      localStaticPrivate: decodedLocalStaticPrivate,
      localStaticPublic: decodedLocalStaticPublic,
      remoteStaticPublic: decodedRemoteStaticPublic,
      grantsHash: decodedGrantsHash,
      profiles: decodedProfiles,
      transport: decodedTransport,
      createdAtMilliseconds: decodedCreatedAtMilliseconds,
      storageConfirmed: decodedStorageConfirmed
    )
    record.lastSessionAtMilliseconds = decodedLastSessionAt
    return decodedForgottenAt.map(record.forgotten(at:)) ?? record
  }

  /// Whether the 30 days a forgotten record keeps its key have passed
  /// (§4.6 item 3).
  internal func revocationNoticeExpired(nowMilliseconds: UInt64) -> Bool {
    guard let forgottenAtMilliseconds else { return false }
    let window = Self.revocationNoticeDays * Self.millisecondsPerDay
    let (deadline, overflowed) = forgottenAtMilliseconds.addingReportingOverflow(window)
    return !overflowed && nowMilliseconds >= deadline
  }

  internal func encoded() throws -> Data {
    try encoded(
      forgottenAtMilliseconds: forgottenAtMilliseconds,
      lastSessionAtMilliseconds: lastSessionAtMilliseconds)
  }

  private func encoded(
    forgottenAtMilliseconds: UInt64?, lastSessionAtMilliseconds: UInt64?
  ) throws -> Data {
    let value = WireValue.map([
      "format_version": .unsigned(pairRecordFormatVersion),
      "pair_id": .bytes(pairIdentifier),
      "role": .text(role.rawValue),
      "local_static_private": .bytes(localStaticPrivate),
      "local_static_public": .bytes(localStaticPublic),
      "remote_static_public": .bytes(remoteStaticPublic),
      "grants_hash": .bytes(grantsHash),
      "profiles": .array(profiles.map { .text($0.rawValue) }),
      "transport_profile": .text(transport.profile),
      "candidate_id": .text(transport.candidateIdentifier),
      "transport_parameters": .map(transport.parameters),
      "created_at_ms": .unsigned(createdAtMilliseconds),
      "storage_confirmed": .boolean(storageConfirmed),
      "forgotten_at_ms": forgottenAtMilliseconds.map { .unsigned($0) } ?? .null,
      "last_session_at_ms": lastSessionAtMilliseconds.map { .unsigned($0) } ?? .null,
    ])
    do {
      return try value.encoded()
    } catch {
      throw PairRecordError.invalidInput
    }
  }

  /// This record in its confirmed form, once the peer's `pairing.stored`
  /// has arrived.
  internal func confirmed() -> Self {
    var record = self
    record.storageConfirmed = true
    return record
  }

  /// This record forgotten by the local user, or expired, at
  /// `forgottenAtMilliseconds`.
  internal func forgotten(at forgottenAtMilliseconds: UInt64) -> Self {
    var record = self
    record.forgottenAtMilliseconds = forgottenAtMilliseconds
    return record
  }

  /// One pairing's idle-expiry check at `nowMilliseconds`, milliseconds
  /// since the Unix epoch (§4.6 item 5).
  ///
  /// `sessionEstablished` says whether a session to the pairing is
  /// established now. With one, the sweep records `nowMilliseconds` and
  /// keeps the pairing, whatever time was recorded before, so no order of
  /// calls expires a pairing in session; the recorded time never moves
  /// back. Without one, the pairing expires once
  /// ``pairingIdleExpiryMilliseconds`` have passed since its latest recorded
  /// session, or since its creation while it has had none. A record that is
  /// not active, one the peer never confirmed or one already forgotten, is
  /// kept as it is: §4.3 item 4 and §4.6 item 3 govern it.
  ///
  /// A change is stored before it is made: the sweep hands the changed
  /// record, encoded, to `store` and changes this record only when `store`
  /// returned. With nothing to change it calls nothing. A store that throws
  /// leaves the record as it was, so the next sweep repeats the whole step.
  internal mutating func sweep(
    nowMilliseconds: UInt64,
    sessionEstablished: Bool,
    store: (Data) throws -> Void
  ) throws -> PairRecordSweepOutcome {
    let plan = sweepPlan(nowMilliseconds: nowMilliseconds, sessionEstablished: sessionEstablished)
    guard plan.outcome != .kept else { return .kept }
    try store(
      encoded(
        forgottenAtMilliseconds: plan.forgottenAtMilliseconds,
        lastSessionAtMilliseconds: plan.lastSessionAtMilliseconds))
    forgottenAtMilliseconds = plan.forgottenAtMilliseconds
    lastSessionAtMilliseconds = plan.lastSessionAtMilliseconds
    return plan.outcome
  }

  /// What ``sweep(nowMilliseconds:sessionEstablished:store:)`` would leave in
  /// this record, without changing it.
  private func sweepPlan(nowMilliseconds: UInt64, sessionEstablished: Bool) -> PairRecordSweepPlan {
    let unchanged = PairRecordSweepPlan(
      outcome: .kept,
      lastSessionAtMilliseconds: lastSessionAtMilliseconds,
      forgottenAtMilliseconds: forgottenAtMilliseconds)
    guard storageConfirmed, forgottenAtMilliseconds == nil else { return unchanged }
    if sessionEstablished {
      return PairRecordSweepPlan(
        outcome: .recorded,
        lastSessionAtMilliseconds: max(
          lastSessionAtMilliseconds ?? nowMilliseconds, nowMilliseconds),
        forgottenAtMilliseconds: forgottenAtMilliseconds)
    }
    guard idleLimitReached(nowMilliseconds: nowMilliseconds) else { return unchanged }
    return PairRecordSweepPlan(
      outcome: .expired,
      lastSessionAtMilliseconds: lastSessionAtMilliseconds,
      forgottenAtMilliseconds: nowMilliseconds)
  }

  /// Whether ``pairingIdleExpiryMilliseconds`` have passed at
  /// `nowMilliseconds` since the later of the pairing's creation and its
  /// latest recorded session.
  private func idleLimitReached(nowMilliseconds: UInt64) -> Bool {
    let since = max(createdAtMilliseconds, lastSessionAtMilliseconds ?? createdAtMilliseconds)
    let idle = nowMilliseconds > since ? nowMilliseconds - since : 0
    return idle >= Self.pairingIdleExpiryMilliseconds
  }
}
