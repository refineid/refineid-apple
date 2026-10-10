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

/// The `mode=session` record announcing the 4 most recently used pairings.
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
