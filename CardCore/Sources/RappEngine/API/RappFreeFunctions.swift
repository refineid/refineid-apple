// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

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

/// The preamble a dialing proxy sends to open a pairing ceremony.
public func rappStreamPairingPreamble() -> Data {
  // The pairing preamble carries no token, so its encoding cannot fail.
  (try? StreamRendezvous.pairing.encoded()) ?? Data()
}

/// The public parameters of a stream candidate advertising `endpoints`.
///
/// The engine owns the shape, so a requester states where it listens and
/// never assembles the map itself.
///
/// - Throws: ``RappBindingError/InvalidInput`` when there are no endpoints,
///   more than the profile allows, or one is longer than it allows.
public func rappStreamCandidateParameters(endpoints: [String]) throws -> Data {
  guard !endpoints.isEmpty, endpoints.count <= StreamProfile.maximumEndpoints else {
    throw RappBindingError.InvalidInput
  }
  for endpoint in endpoints
  where endpoint.isEmpty || endpoint.utf8.count > StreamProfile.maximumEndpointBytes {
    throw RappBindingError.InvalidInput
  }
  do {
    let parameters = WireValue.map([
      StreamProfile.endpointsKey: .array(endpoints.map(WireValue.text))
    ])
    return try parameters.encoded()
  } catch {
    throw RappBindingError.InvalidInput
  }
}

/// The name of the stream transport profile.
public func rappStreamProfileName() -> String {
  StreamProfile.name
}

/// The preamble a dialing proxy sends to reach a stored pairing.
///
/// - Throws: ``RappBindingError/InvalidInput`` when the token is
///   not the size the specification fixes.
public func rappStreamSessionPreamble(rendezvousToken: Data) throws -> Data {
  guard rendezvousToken.count == StreamRendezvous.tokenSize else {
    throw RappBindingError.InvalidInput
  }
  do {
    return try StreamRendezvous.session(token: rendezvousToken).encoded()
  } catch {
    throw RappBindingError.InvalidInput
  }
}

/// The preamble a central sends to open a BLE pairing ceremony.
public func rappBlePairingPreamble() -> Data {
  (try? BleRendezvous.pairing.encoded()) ?? Data()
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

/// The preamble a central sends to reach a stored pairing over BLE.
public func rappBleSessionPreamble(rendezvousToken: Data) throws -> Data {
  guard rendezvousToken.count == BleRendezvous.tokenSize else {
    throw RappBindingError.InvalidInput
  }
  do {
    return try BleRendezvous.session(token: rendezvousToken).encoded()
  } catch {
    throw RappBindingError.InvalidInput
  }
}
