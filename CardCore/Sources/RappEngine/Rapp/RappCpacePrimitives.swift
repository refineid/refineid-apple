// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

// swiftlint:disable no_magic_numbers

// MARK: - Framing and Formatting Utilities

/// LEB128 encoding of length (draft-irtf-cfrg-cpace-21 Appendix A.1.1).
internal func cpaceEncodeLeb128Len(_ length: Int) -> Data {
  var remainingLength = length
  var out = Data()
  while true {
    if remainingLength < 128 {
      out.append(UInt8(remainingLength))
      break
    }
    let byteVal = (remainingLength & 127) | 128
    out.append(UInt8(byteVal))
    remainingLength >>= 7
  }
  return out
}

/// Prepend LEB128 length to data (draft-irtf-cfrg-cpace-21 Appendix A.1.1).
internal func cpacePrependLen(_ data: Data) -> Data {
  var out = cpaceEncodeLeb128Len(data.count)
  out.append(data)
  return out
}

/// Length-value concatenation (draft-irtf-cfrg-cpace-21 Appendix A.1.3).
internal func cpaceLvCat(_ slices: [Data]) -> Data {
  var out = Data()
  for slice in slices {
    out.append(cpaceEncodeLeb128Len(slice.count))
    out.append(slice)
  }
  return out
}

/// Generator string construction with zero padding (draft-irtf-cfrg-cpace-21 Section 8.1 & Appendix A.2).
internal func cpaceGeneratorString(
  dsi: Data,
  prs: Data,
  channelInfo: Data,
  sid: Data,
  sInBytes: Int
) -> Data {
  let dsiLen = cpaceEncodeLeb128Len(dsi.count).count + dsi.count
  let prsLen = cpaceEncodeLeb128Len(prs.count).count + prs.count
  let used = 1 + prsLen + dsiLen
  let lenZpad = max(0, sInBytes - used)
  let zpad = Data(repeating: 0, count: lenZpad)
  return cpaceLvCat([dsi, prs, zpad, channelInfo, sid])
}

/// Generator string construction with default SHA-512 block size.
internal func cpaceGeneratorString(
  dsi: Data,
  prs: Data,
  channelInfo: Data,
  sid: Data
) -> Data {
  cpaceGeneratorString(
    dsi: dsi,
    prs: prs,
    channelInfo: channelInfo,
    sid: sid,
    sInBytes: RappCpaceConstants.sha512InputBlockSize
  )
}

/// Initiator-responder transcript encoding (draft-irtf-cfrg-cpace-21 Appendix A.3.4).
internal func cpaceTranscriptIR(
  partyAPublic: Data,
  additionalDataA: Data,
  partyBPublic: Data,
  additionalDataB: Data
) -> Data {
  var out = cpaceLvCat([partyAPublic, additionalDataA])
  out.append(cpaceLvCat([partyBPublic, additionalDataB]))
  return out
}

/// Computes the CPace generator point g (draft-irtf-cfrg-cpace-21 Section 8.3).
///
/// An identity generator aborts the offer (RAPP v26.10.1 §6.1.1); there is
/// no fallback point.
internal func cpaceCalculateGenerator(
  prs: Data, channelInfo: Data, sid: Data
) throws -> RistrettoPoint {
  let genStr = cpaceGeneratorString(
    dsi: RappCpaceConstants.dsi,
    prs: prs,
    channelInfo: channelInfo,
    sid: sid,
    sInBytes: RappCpaceConstants.sha512InputBlockSize
  )
  let hash = Data(SHA512.hash(data: genStr))
  let point = RistrettoPoint.fromUniformBytes(hash)
  guard point != RistrettoPoint.identity else { throw RappCpaceError.identityGenerator }
  return point
}

/// Computes the 64-byte intermediate session key (ISK) (draft-irtf-cfrg-cpace-21 Section 7.2).
internal func cpaceCalculateIsk(
  sid: Data,
  sharedPoint: Data,
  transcriptIR: Data
) -> Data {
  var iskInput = cpaceLvCat([RappCpaceConstants.iskDsi, sid, sharedPoint])
  iskInput.append(transcriptIR)
  return Data(SHA512.hash(data: iskInput))
}

/// Computes the 64-byte intermediate session key (ISK) with empty additional data.
internal func cpaceCalculateIsk(
  sid: Data,
  sharedPoint: Data,
  partyAPublic: Data,
  partyBPublic: Data
) -> Data {
  let transcript = cpaceTranscriptIR(
    partyAPublic: partyAPublic,
    additionalDataA: Data(),
    partyBPublic: partyBPublic,
    additionalDataB: Data()
  )
  return cpaceCalculateIsk(
    sid: sid,
    sharedPoint: sharedPoint,
    transcriptIR: transcript
  )
}

/// Derives the 32-byte offer identifier for manual code-based pairing.
///
/// Both peers of a stream or Apple-peer ceremony rebuild the same offer from
/// the code, matching the shared reference implementation's code offers.
public func cpaceDeriveManualOfferId(code: String) throws -> Data {
  let normalized = try cpacePasswordString(code)
  var hasher = SHA256()
  hasher.update(data: Data("RAPP-manual-offer-id-v1".utf8))
  var len = UInt16(normalized.utf8.count).bigEndian
  hasher.update(data: Data(bytes: &len, count: 2))
  hasher.update(data: Data(normalized.utf8))
  return Data(hasher.finalize())
}

/// Reduces a 64-byte wide random integer modulo Curve25519 order L.
///
/// L = 2^252 + 27742317777372353535851937790883648493.
internal func cpaceReduceWideScalar(_ bytes64: Data) -> Data {
  precondition(bytes64.count == 64, "Requires 64 bytes")

  // Curve25519 order L in big-endian bytes (32 bytes)
  let orderBytes = Data([
    16, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    20, 222, 249, 222, 162, 247, 156, 214,
    88, 18, 99, 26, 92, 245, 211, 237,
  ])

  var remainder = Data(repeating: 0, count: 32)

  func isGreaterOrEqual(_ firstData: Data, _ secondData: Data) -> Bool {
    for idx in 0..<32 {
      if firstData[idx] > secondData[idx] { return true }
      if firstData[idx] < secondData[idx] { return false }
    }
    return true
  }

  func subtractOrder(_ accumulator: inout Data) {
    var borrowValue: Int = 0
    for idx in stride(from: 31, through: 0, by: -1) {
      let diff = Int(accumulator[idx]) - Int(orderBytes[idx]) - borrowValue
      if diff < 0 {
        accumulator[idx] = UInt8(diff + 256)
        borrowValue = 1
      } else {
        accumulator[idx] = UInt8(diff)
        borrowValue = 0
      }
    }
  }

  // Iterate from bit 511 down to 0
  for bitIndex in stride(from: 511, through: 0, by: -1) {
    let bytePos = bitIndex / 8
    let bitPos = bitIndex % 8
    let bitVal = (bytes64[bytePos] >> bitPos) & 1

    var carryBit = bitVal
    for idx in stride(from: 31, through: 0, by: -1) {
      let val = (UInt16(remainder[idx]) << 1) | UInt16(carryBit)
      remainder[idx] = UInt8(truncatingIfNeeded: val)
      carryBit = UInt8(val >> 8)
    }

    if isGreaterOrEqual(remainder, orderBytes) {
      subtractOrder(&remainder)
    }
  }

  return Data(remainder.reversed())
}

// swiftlint:enable no_magic_numbers
