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
    operationId: UInt64(RappOperationIdentifier.byteCount),
    livenessChallenge: UInt64(PingChallenge.byteCount))
}

/// How long every pairing offer lives, in milliseconds (RAPP v26.10.29 §3.3
/// item 7).
public func rappOfferTtlMs() -> UInt64 {
  OfferLimit.offerLifetimeMilliseconds
}

/// How long a requester keeps offering a certificate the custodian
/// confirmed, in milliseconds, while no session is open or the custodian
/// reports absence and no report of the card present arrives (RAPP v26.10.29
/// §8.4 item 3).
public func rappIdentityOfferGraceMs() -> UInt64 {
  IdentityOfferGrace.milliseconds
}

/// How long a requester that quits waits for its `service_withdrawn` closes
/// to leave before it exits, and one whose holder turned remote use off
/// waits for its `pairing_revoked` closes, in milliseconds (RAPP v26.10.29
/// §4.5 item 8, §4.6 item 6).
public func rappQuitWithdrawalBoundMs() -> UInt64 {
  QuitWithdrawalBound.milliseconds
}

/// How long a pairing lives without an established session before it
/// expires, in milliseconds (RAPP v26.10.29 §4.6 item 5).
public func rappPairingIdleExpiryMs() -> UInt64 {
  PairRecord.pairingIdleExpiryMilliseconds
}

/// The credential profiles the registry admits, in the order it registers
/// them (RAPP v26.10.29 §9).
public func rappCredentialProfiles() -> [String] {
  ProfileName.allCases.map(\.rawValue)
}

/// The wait a custodian's `pairing-busy` asks for, in milliseconds (RAPP
/// v26.10.29 §4.2, "PairingBusy Schema"): read from the bootstrap answer or
/// the frame in place of CPace step 2 after a call threw
/// ``RappBindingError/CustodianBusy``.
///
/// - Throws: ``RappBindingError/InvalidInput`` when `answer` is not a valid
///   `pairing-busy`.
public func rappPairingBusyRetryAfterMs(_ answer: Data) throws -> UInt64 {
  do {
    return try PairingBusy.decode(answer).retryAfterMilliseconds
  } catch {
    throw RappBindingError.InvalidInput
  }
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

/// The candidate identifier registered for a transport profile.
///
/// The offer entry of `transportProfile` carries it (RAPP v26.10.29 §2.2);
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

/// The `mode=session` record announcing the discovery hints of the 4 most
/// recently used pairings (RAPP transport and discovery hierarchy §4.3); no
/// candidates give the minimal record.
public func rappSessionRecord(candidates: [RappAnnouncementCandidate]) -> [RappTxtEntry] {
  DiscoveryRecord.assemble(candidates.map(\.engineCandidate)).textEntries.map(RappTxtEntry.init)
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
