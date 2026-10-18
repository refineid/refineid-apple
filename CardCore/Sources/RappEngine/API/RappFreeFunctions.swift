// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// How many random bytes each generated value needs.
///
/// The engine states the sizes; the caller owns the random source.
public func rappRandomByteCounts() -> RappRandomByteCounts {
  RappRandomByteCounts(
    offerId: UInt64(OfferLimit.offerIdentifierSize),
    cpaceScalarRandom: UInt64(RappCpaceConstants.wideScalarSize),
    sessionReadyNonce: UInt64(FlowLimit.readyNonce),
    operationId: UInt64(OperationSize.operationIdentifier),
    livenessChallenge: UInt64(PingChallenge.byteCount))
}

/// The stream transport's pairing preamble.
public func rappStreamPairingPreamble() -> Data {
  // The pairing preamble of a registered profile carries no routing, so
  // its encoding cannot fail.
  (try? RoutingPreamble.pairing.encoded(profile: StreamProfile.name)) ?? Data()
}

/// The name of the stream transport profile.
public func rappStreamProfileName() -> String {
  StreamProfile.name
}

/// The public parameters of a BLE candidate advertising a `serviceUUID` and optional `psm`.
public func rappBleCandidateParameters(
  serviceUUID: String = BleProfile.defaultServiceUUIDString,
  psm: UInt16? = nil
) throws -> Data {
  guard !serviceUUID.isEmpty, serviceUUID.utf8.count <= BleProfile.maxServiceUUIDByteCount else {
    throw RappBindingError.InvalidInput
  }
  var map: [String: WireValue] = [
    BleProfile.serviceUUIDKey: .text(serviceUUID)
  ]
  if let psm {
    map[BleProfile.psmKey] = .unsigned(UInt64(psm))
  }
  do {
    let parameters = WireValue.map(map)
    return try parameters.encoded()
  } catch {
    throw RappBindingError.InvalidInput
  }
}

/// The name of the BLE transport profile.
public func rappBleProfileName() -> String {
  BleProfile.name
}

/// The candidate identifier registered for a transport profile.
///
/// The offer entry of `transportProfile` carries it (RAPP v26.10.9 §2.2);
/// an unregistered profile has none.
public func rappCandidateIdentifier(transportProfile: String) -> String? {
  TransportRegistry.entry(for: transportProfile)?.candidateIdentifier
}

/// The pairing preamble of a transport profile.
public func rappPairingPreamble(transportProfile: String) throws -> Data {
  do {
    return try RoutingPreamble.pairing.encoded(profile: transportProfile)
  } catch {
    throw RappBindingError.InvalidInput
  }
}

/// The `mode=session` record announcing the 4 most recently used pairings
/// and, when `retentions` hold a revocation still inside its 30 days, the
/// `revoked` attribute for `instance` at `unixTimeSeconds` (RAPP v26.10.18
/// §4.6 item 4).
///
/// Each retention is the encoded value ``RappPairRecord/revoke(vault:revokedAtMs:)``
/// returned. One that does not decode, or whose window has run out, is
/// left out; ``rappRevocationRetentionExpired(retention:unixTimeSeconds:)``
/// tells the caller which to delete.
///
/// - Throws: ``RappBindingError/InvalidInput`` for an instance name that
///   cannot carry a hint, and ``RappBindingError/LocalStateFailure`` when
///   the random source fails.
public func rappSessionRecord(
  candidates: [RappAnnouncementCandidate],
  retentions: [Data],
  instance: String,
  unixTimeSeconds: UInt64
) throws -> [RappTxtEntry] {
  var announcement: RevokedAnnouncement?
  if !retentions.isEmpty {
    guard let name = InstanceName(instance) else { throw RappBindingError.InvalidInput }
    let nowMilliseconds = rappMilliseconds(unixTimeSeconds: unixTimeSeconds)
    let epoch = DiscoveryRecord.epoch(unixTimeSeconds: unixTimeSeconds)
    let announced = RevocationRetention.candidates(
      retentions.compactMap { try? RevocationRetention.decode($0) },
      instance: name, epoch: epoch, nowMilliseconds: nowMilliseconds)
    if !announced.isEmpty {
      guard let assembled = RevokedAnnouncement.assemble(announced, random: rappRandomBytes)
      else { throw RappBindingError.LocalStateFailure }
      announcement = assembled
    }
  }
  return DiscoveryRecord.assemble(candidates.map(\.engineCandidate), revoked: announcement)
    .textEntries.map(RappTxtEntry.init)
}

/// Whether an encoded revocation retention may be deleted at `unixTimeSeconds`.
///
/// It may once its 30-day announcement window has run out (RAPP v26.10.18
/// §4.6 item 4). A retention that does not decode is expired.
public func rappRevocationRetentionExpired(
  retention: Data, unixTimeSeconds: UInt64
) -> Bool {
  guard let decoded = try? RevocationRetention.decode(retention) else { return true }
  return decoded.isExpired(nowMilliseconds: rappMilliseconds(unixTimeSeconds: unixTimeSeconds))
}

/// `unixTimeSeconds` in milliseconds, saturating.
private func rappMilliseconds(unixTimeSeconds: UInt64) -> UInt64 {
  let now = unixTimeSeconds.multipliedReportingOverflow(
    by: RevocationRetention.millisecondsPerSecond)
  return now.overflow ? UInt64.max : now.partialValue
}

/// The `mode=withdrawn` record announcing the 8 most recently used
/// pairings among random fillers.
public func rappWithdrawnRecord(candidates: [RappAnnouncementCandidate]) throws -> [RappTxtEntry] {
  guard
    let record = WithdrawnRecord.assemble(
      candidates.map(\.engineCandidate), random: rappRandomBytes)
  else { throw RappBindingError.LocalStateFailure }
  return record.textEntries.map(RappTxtEntry.init)
}

/// `count` bytes from the system random source, or `nil` when it fails.
internal func rappRandomBytes(_ count: Int) -> Data? {
  var bytes = Data(count: count)
  let status = bytes.withUnsafeMutableBytes { buffer in
    guard let base = buffer.baseAddress else { return errSecParam }
    return SecRandomCopyBytes(kSecRandomDefault, count, base)
  }
  return status == errSecSuccess ? bytes : nil
}
