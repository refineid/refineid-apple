// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// AES-CMAC, the message authentication code of RFC 4493 and NIST SP 800-38B.
///
/// Neither CryptoKit nor CommonCrypto exposes CMAC, so it is built here over
/// the single-block cipher in `AesCbc`. The construction is key-length
/// agnostic: the FINEID PACE profile uses AES-256, while the published
/// known-answer vectors that gate this code are stated for AES-128 and
/// AES-256 alike.
///
/// PACE mutual authentication compares the full tag; ISO 7816-4 secure
/// messaging puts only its first eight bytes in the cryptographic checksum
/// data object. Both lengths are named here so no caller truncates by hand.
///
/// Tag comparison is the caller's responsibility and must be done in
/// constant time on any value that a card or a peer supplied.
///
/// Provenance: lifted from the RefineID iOS browser donor
/// `Sources/RefineIDBrowserKit/Crypto/CMAC.swift`.
public enum AesCmac {
  /// The full CMAC tag length in bytes, which is one AES block.
  public static let tagLength = AesCbc.blockSize

  /// The truncated tag length ISO 7816-4 secure messaging carries in its
  /// cryptographic checksum data object.
  public static let secureMessagingTagLength = 8

  /// The RFC 4493 section 2.3 constant Rb for a 128-bit block: zero bytes
  /// up to the final one, whose value is named in `AesCmacValues`.
  private static let rbConstant: Data = {
    var value = Data(repeating: 0, count: AesCbc.blockSize - 1)
    value.append(AesCmacValues.rbLowByte)
    return value
  }()

  /// The full CMAC tag of `message` under `key`.
  ///
  /// An empty message is legitimate and has a defined tag; the padded-block
  /// subkey covers it, which is what keeps the empty and the all-zero
  /// single-block messages distinguishable.
  public static func tag(key: Data, message: Data) throws -> Data {
    let subkeys = try Self.subkeys(key: key)
    let isBlockAligned = !message.isEmpty && message.count.isMultiple(of: AesCbc.blockSize)
    let finalBlock = Self.finalBlock(
      message: message,
      isBlockAligned: isBlockAligned,
      subkeys: subkeys
    )
    let chainedBlockCount =
      isBlockAligned
      ? (message.count / AesCbc.blockSize) - 1
      : message.count / AesCbc.blockSize

    var chained = Data(repeating: 0, count: AesCbc.blockSize)
    var remaining = message
    for _ in 0..<chainedBlockCount {
      chained = try AesCbc.encryptBlock(
        key: key,
        block: Self.exclusiveOr(chained, remaining.prefix(AesCbc.blockSize))
      )
      remaining = remaining.dropFirst(AesCbc.blockSize)
    }
    return try AesCbc.encryptBlock(key: key, block: Self.exclusiveOr(chained, finalBlock))
  }

  /// The CMAC tag truncated to the length secure messaging transmits.
  public static func secureMessagingTag(key: Data, message: Data) throws -> Data {
    try Data(Self.tag(key: key, message: message).prefix(Self.secureMessagingTagLength))
  }

  /// The two subkeys of RFC 4493 section 2.3, derived by encrypting an
  /// all-zero block and shifting the result.
  ///
  /// `fullBlock` masks a message whose length is a non-zero multiple of the
  /// block size; `paddedBlock` masks every other message, after padding.
  private static func subkeys(key: Data) throws -> (fullBlock: Data, paddedBlock: Data) {
    let seed = try AesCbc.encryptBlock(
      key: key,
      block: Data(repeating: 0, count: AesCbc.blockSize)
    )
    let firstShift = Self.shiftedLeftOneBit(seed)
    let fullBlock =
      firstShift.overflowed
      ? Self.exclusiveOr(firstShift.shifted, Self.rbConstant)
      : firstShift.shifted
    let secondShift = Self.shiftedLeftOneBit(fullBlock)
    let paddedBlock =
      secondShift.overflowed
      ? Self.exclusiveOr(secondShift.shifted, Self.rbConstant)
      : secondShift.shifted
    return (fullBlock, paddedBlock)
  }

  /// The last block of the chain, masked with the subkey its shape selects.
  ///
  /// A block-aligned message contributes its final block unchanged; anything
  /// else contributes its trailing partial block, padded.
  private static func finalBlock(
    message: Data,
    isBlockAligned: Bool,
    subkeys: (fullBlock: Data, paddedBlock: Data)
  ) -> Data {
    guard !isBlockAligned else {
      return Self.exclusiveOr(message.suffix(AesCbc.blockSize), subkeys.fullBlock)
    }
    var padded = Data(message.suffix(message.count % AesCbc.blockSize))
    padded.append(AesCmacValues.paddingMarker)
    padded.append(contentsOf: repeatElement(0, count: AesCbc.blockSize - padded.count))
    return Self.exclusiveOr(padded, subkeys.paddedBlock)
  }

  /// Shifts a block left by one bit, reporting the bit shifted out of the
  /// most significant end.
  ///
  /// Reporting the carry out is what lets the subkey derivation decide about
  /// Rb without indexing into a buffer whose length it would have to assume.
  private static func shiftedLeftOneBit(_ block: Data) -> (shifted: Data, overflowed: Bool) {
    var reversedResult: [UInt8] = []
    reversedResult.reserveCapacity(block.count)
    var carry: UInt8 = 0
    for byte in block.reversed() {
      reversedResult.append((byte << 1) | carry)
      carry = (byte & AesCmacValues.highBitMask) != 0 ? 1 : 0
    }
    return (Data(reversedResult.reversed()), carry != 0)
  }

  /// The byte-wise exclusive or of two buffers, over their common length.
  private static func exclusiveOr(_ left: Data, _ right: Data) -> Data {
    Data(zip(left, right).map { $0 ^ $1 })
  }
}
