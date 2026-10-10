// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

// The CPaceRistretto255 KC2 profile of RAPP v26.10.9 §6.1: the requester is
// initiator A and sends Y_A; the custodian is responder B and answers with
// Y_B and its tag T_B; the requester closes with T_A. Both derive the
// pre-shared key the Noise_XXpsk3 pairing handshake consumes.

/// The six-character code alphabet of RAPP v26.10.9 §3.1.
private let codeAlphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
private let codeLength = 6

/// The password string for an already canonical pairing code.
///
/// Canonicalization belongs to the user interface (§3.1); the engine
/// accepts only its exact output, six characters of the code alphabet.
internal func cpacePasswordString(_ code: String) throws -> String {
  guard code.count == codeLength, code.allSatisfy(codeAlphabet.contains) else {
    throw RappCpaceError.invalidCode
  }
  return code
}

/// The pairing context C (RAPP v26.10.9 §6.1.1) for one offer hash, bound
/// to the connection's transport profile and its offer entry's candidate.
internal func cpaceKc2Context(
  offerHash: Data, transportProfile: String, candidateIdentifier: String
) throws -> Data {
  let context = WireValue.array([
    .text(RappCpaceConstants.contextDomain),
    wireVersionValue,
    .text(RappCpaceConstants.kc2Suite),
    .text(transportProfile),
    .text(candidateIdentifier),
    .bytes(offerHash),
    .text(RappCpaceConstants.initiatorRole),
    .text(RappCpaceConstants.responderRole),
  ])
  do {
    return try context.encoded()
  } catch {
    throw RappCpaceError.malformedFrame
  }
}

/// TH = SHA-512(lv_cat("RAPP-CPACE-TRANSCRIPT-v2", SID, C, Y_A, Y_B)).
internal func cpaceKc2TranscriptHash(
  sid: Data, context: Data, partyAPublic: Data, partyBPublic: Data
) -> Data {
  Data(
    SHA512.hash(
      data: cpaceLvCat([
        RappCpaceConstants.transcriptDomain, sid, context, partyAPublic, partyBPublic,
      ])))
}

/// Compares two tags without an early exit on the first differing byte.
internal func cpaceTagsMatch(_ expected: Data, _ received: Data) -> Bool {
  guard expected.count == received.count else { return false }
  var difference: UInt8 = 0
  for (left, right) in zip(expected, received) {
    difference |= left ^ right
  }
  return difference == 0
}

/// A non-zero scalar by 64-byte wide reduction (§6.1.1 Option B).
internal func cpaceSampleScalar(_ randomBytes: Data) throws -> Data {
  guard randomBytes.count == RappCpaceConstants.wideScalarSize else {
    throw RappCpaceError.invalidScalar
  }
  let scalar = cpaceReduceWideScalar(randomBytes)
  guard scalar.contains(where: { $0 != 0 }) else { throw RappCpaceError.invalidScalar }
  return scalar
}

/// A decoded peer element: canonical, and not the identity.
internal func cpacePeerPoint(_ bytes: Data) throws -> RistrettoPoint {
  guard bytes.count == RappCpaceConstants.pointSize,
    let point = RistrettoPoint.decompress(bytes), point != RistrettoPoint.identity
  else { throw RappCpaceError.invalidPoint }
  return point
}

/// The shared element K, refused when it is the identity.
internal func cpaceSharedPoint(_ peer: RistrettoPoint, scalar: Data) throws -> Data {
  let shared = peer.scalarMul(scalar)
  guard shared != RistrettoPoint.identity else { throw RappCpaceError.identitySharedPoint }
  return shared.compress()
}

/// The generator G for one code, context and offer identifier.
internal func cpaceKc2Generator(code: String, context: Data, sid: Data) throws -> RistrettoPoint {
  guard sid.count == RappCpaceConstants.offerIdSize else { throw RappCpaceError.invalidCode }
  let password = Data(try cpacePasswordString(code).utf8)
  return try cpaceCalculateGenerator(prs: password, channelInfo: context, sid: sid)
}

/// The keys both roles derive once Y_A, Y_B and K are known.
internal func cpaceKc2Keys(
  sid: Data, context: Data, sharedPoint: Data, partyAPublic: Data, partyBPublic: Data
) -> CpaceKc2Keys {
  CpaceKc2Keys(
    intermediateSessionKey: cpaceCalculateIsk(
      sid: sid, sharedPoint: sharedPoint, partyAPublic: partyAPublic,
      partyBPublic: partyBPublic),
    transcriptHash: cpaceKc2TranscriptHash(
      sid: sid, context: context, partyAPublic: partyAPublic, partyBPublic: partyBPublic))
}
