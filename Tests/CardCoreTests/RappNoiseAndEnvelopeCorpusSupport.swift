// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

internal enum RappNoiseAndEnvelopeCorpusSupport {
  internal enum Constants {
    internal static let majorAdditionalInfoMask: UInt8 = 0x1f
    internal static let majorLengthRange = 1...2
    internal static let maxDecodeDepth = 16
    internal static let maxCollectionCount = 128
    internal static let maxReadLength = 16_384
    internal static let pairLength = 2
    internal static let hexRadix = 16
    internal static let majorLengthMax: UInt8 = 23
    internal static let nextValue8bit: UInt8 = 24
    internal static let max8bit = UInt64(UInt8.max)
    internal static let nextValue16bit: UInt8 = 25
    internal static let min16bit: UInt64 = 0x100
    internal static let max16bit: UInt64 = 0xffff
    internal static let nextValue32bit: UInt8 = 26
    internal static let max32bit: UInt64 = 0xffff_ffff
    internal static let nextValue64bit: UInt8 = 27
    internal static let majorUnsigned = CBORMajor.unsigned.rawValue
    internal static let majorBytes = CBORMajor.bytes.rawValue
    internal static let majorText = CBORMajor.text.rawValue
    internal static let majorArray = CBORMajor.array.rawValue
    internal static let majorMap = CBORMajor.map.rawValue
    internal static let byteShift = 8
    internal static let byteCountUInt16 = 2
    internal static let byteCountUInt32 = 4
    internal static let byteCountUInt64 = 8
    internal static let wireMajor: UInt64 = 26
    internal static let wireMinor: UInt64 = 9
    internal static let wirePatch: UInt64 = 13
    internal static let versionLength = 3
    internal static let patchIndex = 2
    internal static let sessionIDLength = 16
    internal static let challengeLength = 32
    internal static let hashPrefixLength = 16
  }

  internal struct WireVersion: Sendable, Equatable {
    internal let major: UInt64
    internal let minor: UInt64
    internal let patch: UInt64
  }

  private enum CBORMajor: UInt8 {
    case array = 4
    case bytes = 2
    case map = 5
    case text = 3
    case unsigned = 0
    case unusedForBitFlag = 1
  }

  internal enum CBORValue: Equatable {
    case array([Self])
    case bytes(Data)
    case map([String: Self])
    case text(String)
    case unsigned(UInt64)
  }

  internal enum CBORDecodeError: Error {
    case duplicateKey
    case invalidUTF8
    case limitExceeded
    case truncated
    case unsupported
  }

  internal static let wire = WireVersion(
    major: Constants.wireMajor,
    minor: Constants.wireMinor,
    patch: Constants.wirePatch
  )

  internal static func encodeUnsigned(_ value: UInt64) -> Data {
    encodeMajor(Constants.majorUnsigned, value: value)
  }

  internal static func encodeBytes(_ value: Data) -> Data {
    var result = encodeMajor(Constants.majorBytes, value: UInt64(value.count))
    result.append(value)
    return result
  }

  internal static func encodeText(_ value: String) -> Data {
    let utf8 = Data(value.utf8)
    var result = encodeMajor(Constants.majorText, value: UInt64(utf8.count))
    result.append(utf8)
    return result
  }

  internal static func encodeArray(_ values: [Data]) -> Data {
    var result = encodeMajor(Constants.majorArray, value: UInt64(values.count))
    values.forEach { result.append($0) }
    return result
  }

  internal static func encodeHex(_ value: Data) -> String {
    value.map { String(format: "%02x", $0) }.joined()
  }

  internal static func decodeHex(_ value: String) -> Data {
    decodedHex(value)
  }

  private static func decodedHex(_ value: String) -> Data {
    precondition(
      value.count.isMultiple(of: Constants.pairLength),
      "Odd hex length")
    var result = Data()
    result.reserveCapacity(value.count / Constants.pairLength)
    var index = value.startIndex
    while index < value.endIndex {
      let next = value.index(index, offsetBy: Constants.pairLength)
      guard let byte = UInt8(value[index..<next], radix: Constants.hexRadix) else {
        preconditionFailure("Invalid hex")
      }
      result.append(byte)
      index = next
    }
    return result
  }

  private static func encodeMajor(_ major: UInt8, value: UInt64) -> Data {
    let prefix = major << 5
    switch value {
    case 0...UInt64(Constants.majorLengthMax):
      return Data([prefix | UInt8(value)])

    case UInt64(Constants.nextValue8bit)...Constants.max8bit:
      return Data([prefix | UInt8(Constants.nextValue8bit), UInt8(value)])

    case UInt64(Constants.min16bit)...Constants.max16bit:
      return Data([
        prefix | UInt8(Constants.nextValue16bit),
        UInt8(value >> UInt8(Constants.byteShift)),
        UInt8(value),
      ])

    case UInt64(Constants.nextValue32bit)...Constants.max32bit:
      return Data(
        [prefix | UInt8(Constants.nextValue32bit)]
          + (0..<Constants.byteCountUInt32).reversed().map { index in
            UInt8(value >> UInt64(index * Constants.byteShift))
          })

    default:
      return Data(
        [prefix | UInt8(Constants.nextValue64bit)]
          + (0..<Constants.byteCountUInt64).reversed().map { index in
            UInt8(value >> UInt64(index * Constants.byteShift))
          })
    }
  }

  internal static func corpus(
    from repositoryRoot: URL
  ) throws -> Corpus {
    let url =
      repositoryRoot
      .appendingPathComponent("Documentation")
      .appendingPathComponent("rapp-conformance")
      .appendingPathComponent("rapp-v26.9.13.json")
    return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
  }

  internal static func deriveIdentifier(domain: String, handshakeHash: Data) -> String {
    var input = Data(domain.utf8)
    input.append(handshakeHash)
    return encodeHex(Data(SHA256.hash(data: input)).prefix(Constants.hashPrefixLength))
  }

  internal static func validateVectorHex(_ value: String) -> Data {
    decodedHex(value)
  }
}
