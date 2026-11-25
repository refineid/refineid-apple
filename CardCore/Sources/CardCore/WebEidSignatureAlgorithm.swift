// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// One Web eID signature algorithm descriptor returned by `get-signing-certificate`
/// and `sign`.
public struct WebEidSignatureAlgorithm: Codable, Equatable, Sendable {
  /// Asymmetric algorithm family (`"ECC"` or `"RSA"`).
  public let cryptoAlgorithm: String

  /// Hash algorithm name (`"SHA-256"`, `"SHA-384"`, `"SHA-512"`).
  public let hashFunction: String

  /// Padding scheme (`"NONE"` or `"PKCS1.5"`).
  public let paddingScheme: String

  /// Creates a signature algorithm descriptor.
  public init(cryptoAlgorithm: String, hashFunction: String, paddingScheme: String) {
    self.cryptoAlgorithm = cryptoAlgorithm
    self.hashFunction = hashFunction
    self.paddingScheme = paddingScheme
  }

  /// Serializes the descriptor into the dictionary shape expected by `web-eid.js`.
  public func toDictionary() -> [String: String] {
    [
      "cryptoAlgorithm": cryptoAlgorithm,
      "hashFunction": hashFunction,
      "paddingScheme": paddingScheme,
    ]
  }
}
