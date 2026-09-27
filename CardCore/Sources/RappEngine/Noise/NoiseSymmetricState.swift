// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// The chaining key and transcript hash shared by both handshake parties.
internal struct NoiseSymmetricState {
  /// Outputs the Noise key-derivation chain produces for each mixing step.
  private enum DerivedOutputs {
    static let mixKey = 2
    static let mixKeyAndHash = 3
    static let split = 2
  }

  private enum HashFunction {
    case sha256
    case sha512

    var hashLength: Int {
      switch self {
      case .sha256:
        return NoiseSizes.sha256HashLength
      case .sha512:
        return NoiseSizes.sha512HashLength
      }
    }

    func hash(data: Data) -> Data {
      switch self {
      case .sha256:
        return Data(SHA256.hash(data: data))
      case .sha512:
        return Data(SHA512.hash(data: data))
      }
    }

    func hmac(for data: Data, using key: SymmetricKey) -> Data {
      switch self {
      case .sha256:
        return Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
      case .sha512:
        return Data(HMAC<SHA512>.authenticationCode(for: data, using: key))
      }
    }
  }

  /// Noise numbers derivation outputs from one, not zero.
  private static let firstOutputIndex = 1

  /// Positions of the derived outputs, in the order the chain emits them.
  private static let chainOutput = 0
  private static let hashOutput = 1
  private static let keyOutput = 2

  private let hashFunction: HashFunction
  private var chainingKey: Data
  internal private(set) var handshakeHash: Data
  internal var cipher = NoiseCipherState()

  internal init(protocolName: String) {
    let chosenHash: HashFunction
    if protocolName.hasSuffix("_SHA256") {
      chosenHash = .sha256
    } else {
      chosenHash = .sha512
    }
    self.hashFunction = chosenHash

    let name = Data(protocolName.utf8)
    let hashLength = chosenHash.hashLength
    if name.count <= hashLength {
      handshakeHash = name + Data(repeating: 0, count: hashLength - name.count)
    } else {
      handshakeHash = chosenHash.hash(data: name)
    }
    chainingKey = handshakeHash
  }

  /// The Noise key-derivation chain: repeated HMAC over the chaining key.
  private func derive(material: Data, outputs: Int) -> [Data] {
    let temporaryKey = SymmetricKey(
      data: hashFunction.hmac(
        for: material, using: SymmetricKey(data: chainingKey)))
    var results: [Data] = []
    var previous = Data()
    for index in Self.firstOutputIndex...outputs {
      let input = previous + Data([UInt8(index)])
      let output = hashFunction.hmac(for: input, using: temporaryKey)
      results.append(output)
      previous = output
    }
    return results
  }

  internal mutating func mixHash(_ data: Data) {
    handshakeHash = hashFunction.hash(data: handshakeHash + data)
  }

  internal mutating func mixKey(_ material: Data) {
    let outputs = derive(material: material, outputs: DerivedOutputs.mixKey)
    chainingKey = outputs[Self.chainOutput]
    cipher.initializeKey(Data(outputs[Self.hashOutput].prefix(NoiseSizes.keyLength)))
  }

  internal mutating func mixKeyAndHash(_ material: Data) {
    let outputs = derive(material: material, outputs: DerivedOutputs.mixKeyAndHash)
    chainingKey = outputs[Self.chainOutput]
    mixHash(outputs[Self.hashOutput])
    cipher.initializeKey(Data(outputs[Self.keyOutput].prefix(NoiseSizes.keyLength)))
  }

  internal mutating func encryptAndHash(_ plaintext: Data) throws -> Data {
    let ciphertext = try cipher.encrypt(associatedData: handshakeHash, plaintext: plaintext)
    mixHash(ciphertext)
    return ciphertext
  }

  internal mutating func decryptAndHash(_ ciphertext: Data) throws -> Data {
    let plaintext = try cipher.decrypt(associatedData: handshakeHash, ciphertext: ciphertext)
    mixHash(ciphertext)
    return plaintext
  }

  /// The two transport keys, in initiator-sends-first order.
  internal func split() -> (Data, Data) {
    let outputs = derive(material: Data(), outputs: DerivedOutputs.split)
    return (
      Data(outputs[Self.chainOutput].prefix(NoiseSizes.keyLength)),
      Data(outputs[Self.hashOutput].prefix(NoiseSizes.keyLength))
    )
  }
}
