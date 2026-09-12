// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CommonCrypto
import Foundation

/// AES without padding: CBC over a block-aligned buffer, plus the
/// single-block ECB primitive.
///
/// PACE and ISO 7816-4 secure messaging need exactly these two shapes.
/// Padding stays with the caller: the card protocol prescribes ISO 7816-4
/// padding and applies it before encryption, so a buffer that is not already
/// block aligned is a caller bug and is refused rather than silently padded.
/// The single-block operation is the raw block cipher `AesCmac` and the
/// secure-messaging IV derivation are built from, never a mode for bulk data.
///
/// CryptoKit offers neither CBC nor raw block access, so the arithmetic is
/// CommonCrypto's -- the system AES, the same posture as leaning on CryptoKit
/// elsewhere.
///
/// Provenance: lifted from the RefineID iOS browser donor
/// `Sources/RefineIDBrowserKit/Crypto/AES.swift`.
public enum AesCbc {
  /// Why an AES operation was refused.
  ///
  /// Every case is a caller or system fault, never card data, so none of
  /// these values may be shown to the user as a card diagnosis.
  public enum Failure: Error, Equatable {
    /// The input length is not a whole number of blocks; this type never
    /// pads on the caller's behalf.
    case blockAlignment

    /// A single-block operation was given something other than one block.
    case blockLength

    /// The initialization vector is not exactly one block.
    case initializationVectorLength

    /// The key length is not one of the three AES key lengths.
    case keyLength

    /// The system cipher reported a failure.
    case systemCipher
  }

  /// The AES block size in bytes, which is the same for every key length.
  public static let blockSize = kCCBlockSizeAES128

  /// The key lengths in bytes the AES cipher accepts.
  ///
  /// The FINEID PACE profile uses the 256-bit key; the shorter lengths stay
  /// available because the RFC 4493 known-answer vectors that gate `AesCmac`
  /// are stated for AES-128.
  internal static let supportedKeyLengths: Set<Int> = [
    kCCKeySizeAES128,
    kCCKeySizeAES192,
    kCCKeySizeAES256,
  ]

  /// No mode options: CBC with no padding is the system cipher's default.
  private static let noOptions: CCOptions = 0

  /// Encrypts exactly one block with the raw block cipher (ECB).
  ///
  /// This is a primitive, not a mode. The only intended callers are the CMAC
  /// construction and the secure-messaging IV derivation, both of which
  /// encrypt a single block that is never reused under the same key.
  public static func encryptBlock(key: Data, block: Data) throws -> Data {
    guard block.count == Self.blockSize else { throw Failure.blockLength }
    return try Self.crypt(
      operation: CCOperation(kCCEncrypt),
      options: CCOptions(kCCOptionECBMode),
      key: key,
      initializationVector: Data(repeating: 0, count: Self.blockSize),
      input: block
    )
  }

  /// Encrypts a block-aligned plaintext in CBC mode, without padding.
  public static func encrypt(
    key: Data,
    initializationVector: Data,
    plaintext: Data
  ) throws -> Data {
    guard plaintext.count.isMultiple(of: Self.blockSize) else {
      throw Failure.blockAlignment
    }
    return try Self.crypt(
      operation: CCOperation(kCCEncrypt),
      options: Self.noOptions,
      key: key,
      initializationVector: initializationVector,
      input: plaintext
    )
  }

  /// Decrypts a block-aligned ciphertext in CBC mode, without removing
  /// padding.
  ///
  /// The recovered buffer still carries whatever padding the sender applied;
  /// stripping it is the protocol layer's decision, because only that layer
  /// knows which padding the command used.
  public static func decrypt(
    key: Data,
    initializationVector: Data,
    ciphertext: Data
  ) throws -> Data {
    guard ciphertext.count.isMultiple(of: Self.blockSize) else {
      throw Failure.blockAlignment
    }
    return try Self.crypt(
      operation: CCOperation(kCCDecrypt),
      options: Self.noOptions,
      key: key,
      initializationVector: initializationVector,
      input: ciphertext
    )
  }

  /// Runs one system cipher operation after validating every length the
  /// system call would otherwise take on trust.
  private static func crypt(
    operation: CCOperation,
    options: CCOptions,
    key: Data,
    initializationVector: Data,
    input: Data
  ) throws -> Data {
    guard Self.supportedKeyLengths.contains(key.count) else {
      throw Failure.keyLength
    }
    guard initializationVector.count == Self.blockSize else {
      throw Failure.initializationVectorLength
    }
    guard !input.isEmpty else { return Data() }

    var output = Data(repeating: 0, count: input.count + Self.blockSize)
    var producedCount = 0
    let status = key.withUnsafeBytes { keyBytes in
      initializationVector.withUnsafeBytes { vectorBytes in
        input.withUnsafeBytes { inputBytes in
          output.withUnsafeMutableBytes { outputBytes in
            CCCrypt(
              operation,
              CCAlgorithm(kCCAlgorithmAES),
              options,
              keyBytes.baseAddress,
              key.count,
              vectorBytes.baseAddress,
              inputBytes.baseAddress,
              input.count,
              outputBytes.baseAddress,
              outputBytes.count,
              &producedCount
            )
          }
        }
      }
    }
    guard status == CCCryptorStatus(kCCSuccess) else { throw Failure.systemCipher }
    return Data(output.prefix(producedCount))
  }
}
