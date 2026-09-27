// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

// swiftlint:disable no_magic_numbers

/// Ephemeral state for one party in the CPace key exchange.
public struct RappCpaceState: Sendable {
  private static let leb128Limit = 128
  private static let leb128DataMask = 127
  private static let leb128ContinuationBit = 128
  private static let leb128Shift = 7
  private static let maxCodeLength = 64
  private static let lengthPrefixSize = 2
  private static let frameElementCount = 2
  private static let wideScalarByteCount = 64
  private static let orderByteCount = 32
  private static let bitsPerByte = 8
  private static let maxScalarBitIndex = 511
  private static let byteWrapModulus = 256

  /// Whether this party acts as the CPace initiator.
  public let isInitiator: Bool
  /// Context offer identifier binding the CPace transcript.
  public let offerId: Data
  private let scalar: Data
  /// The local party's 32-byte compressed public point.
  public let publicPoint: Data

  /// Initializes a CPace exchange state with the given role, code, offer ID, and 64 bytes of entropy.
  public init(
    isInitiator: Bool,
    pairingCode: String,
    offerId: Data,
    randomBytes64: Data
  ) throws {
    guard offerId.count == RappCpaceConstants.offerIdSize else {
      throw RappCpaceError.invalidCode
    }
    guard randomBytes64.count == Self.wideScalarByteCount else {
      throw RappCpaceError.invalidScalar
    }

    let normalized = try cpaceNormalizeCode(pairingCode)
    let generator = cpaceCalculateGenerator(
      prs: Data(normalized.utf8),
      channelInfo: Data(),
      sid: offerId
    )

    let scalar32 = cpaceReduceWideScalar(randomBytes64)
    if scalar32.allSatisfy({ $0 == 0 }) {
      throw RappCpaceError.invalidScalar
    }

    let myPoint = generator.scalarMul(scalar32)
    let myPublic = myPoint.compress()

    self.isInitiator = isInitiator
    self.offerId = offerId
    self.scalar = scalar32
    self.publicPoint = myPublic
  }

  /// Complete the exchange by processing peer's 32-byte public point.
  ///
  /// Derives the 256-bit PSK using draft-irtf-cfrg-cpace-21 ISK derivation.
  public func finish(peerPublic: Data) throws -> Data {
    guard peerPublic.count == RappCpaceConstants.pointSize else {
      throw RappCpaceError.invalidPoint
    }
    guard let peerPoint = RistrettoPoint.decompress(peerPublic) else {
      throw RappCpaceError.invalidPoint
    }
    if peerPoint == RistrettoPoint.identity {
      throw RappCpaceError.invalidPoint
    }

    let sharedPoint = peerPoint.scalarMul(scalar)
    if sharedPoint == RistrettoPoint.identity {
      throw RappCpaceError.identitySharedPoint
    }

    let sharedPointBytes = sharedPoint.compress()

    let (pointYa, pointYb) = isInitiator ? (publicPoint, peerPublic) : (peerPublic, publicPoint)
    let isk = cpaceCalculateIsk(
      sid: offerId,
      sharedPoint: sharedPointBytes,
      partyAPublic: pointYa,
      partyBPublic: pointYb
    )

    return isk.prefix(RappCpaceConstants.pairingSecretSize)
  }

  /// Produce a deterministic-CBOR binary frame carrying this peer's public group element.
  public func writeMessage() throws -> Data {
    try cpaceEncodeFrame(publicPoint: publicPoint)
  }

  /// Read and verify the peer's binary frame, completing the exchange and deriving the secret.
  public func readMessage(_ frame: Data) throws -> Data {
    let peerPoint = try cpaceDecodeFrame(frame)
    return try finish(peerPublic: peerPoint)
  }
}

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
internal func cpaceCalculateGenerator(prs: Data, channelInfo: Data, sid: Data) -> RistrettoPoint {
  let genStr = cpaceGeneratorString(
    dsi: RappCpaceConstants.dsi,
    prs: prs,
    channelInfo: channelInfo,
    sid: sid,
    sInBytes: RappCpaceConstants.sha512InputBlockSize
  )
  let hash = Data(SHA512.hash(data: genStr))
  let point = RistrettoPoint.fromUniformBytes(hash)
  if point == RistrettoPoint.identity {
    return RistrettoPoint.elligator(Data(repeating: 0, count: RappCpaceConstants.pointSize))
  }
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

/// Normalizes human-entered pairing code (removes whitespace and verifies alphanumeric).
internal func cpaceNormalizeCode(_ code: String) throws -> String {
  let trimmed = code.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
  let cleaned = String(String.UnicodeScalarView(trimmed))
  guard !cleaned.isEmpty, cleaned.count <= 64 else {
    throw RappCpaceError.invalidCode
  }
  guard cleaned.allSatisfy({ $0.isLetter || $0.isNumber }) else {
    throw RappCpaceError.invalidCode
  }
  return cleaned
}

/// Derives the 32-byte offer identifier for manual code-based pairing.
public func cpaceDeriveManualOfferId(code: String) throws -> Data {
  let normalized = try cpaceNormalizeCode(code)
  var hasher = SHA256()
  hasher.update(data: Data("RAPP-manual-offer-id-v1".utf8))
  var len = UInt16(normalized.utf8.count).bigEndian
  hasher.update(data: Data(bytes: &len, count: 2))
  hasher.update(data: Data(normalized.utf8))
  return Data(hasher.finalize())
}

/// Encodes a CPace public point into a deterministic-CBOR binary frame.
///
/// Format: `["RAPP-cpace-v1", bstr .size 32]`.
internal func cpaceEncodeFrame(publicPoint: Data) throws -> Data {
  guard publicPoint.count == RappCpaceConstants.pointSize else {
    throw RappCpaceError.malformedFrame
  }
  let wire = WireValue.array([
    .text(RappCpaceConstants.frameDomain),
    .bytes(publicPoint),
  ])
  do {
    return try wire.encoded()
  } catch {
    throw RappCpaceError.malformedFrame
  }
}

/// Decodes a peer's CPace public point from a binary frame.
///
/// Format: `["RAPP-cpace-v1", bstr .size 32]`.
internal func cpaceDecodeFrame(_ frame: Data) throws -> Data {
  guard let wire = try? decodeDeterministicCbor(frame) else {
    throw RappCpaceError.malformedFrame
  }
  guard case .array(let elements) = wire, elements.count == 2 else {
    throw RappCpaceError.malformedFrame
  }
  guard case .text(let domain) = elements[0], domain == RappCpaceConstants.frameDomain else {
    throw RappCpaceError.malformedFrame
  }
  guard case .bytes(let pointBytes) = elements[1], pointBytes.count == RappCpaceConstants.pointSize
  else {
    throw RappCpaceError.malformedFrame
  }
  return pointBytes
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
