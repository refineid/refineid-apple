// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine
  import Security

  /// System randomness at the byte counts the Rust core publishes.
  public struct RappPlatformEntropy: Sendable {
    private static let cpaceRandomByteCount: UInt64 = 64

    /// Creates a stateless entropy source.
    public init() {
      // platform default
    }

    /// Returns a fresh pairing offer identifier.
    public func offerID() throws -> Data {
      try bytes(count: rappRandomByteCounts().offerId)
    }

    /// Returns a fresh pairing secret.
    public func pairingSecret() throws -> Data {
      try bytes(count: rappRandomByteCounts().pairingSecret)
    }

    /// Returns 64 fresh random bytes for CPace scalar sampling.
    public func cpaceRandom() throws -> Data {
      try bytes(count: Self.cpaceRandomByteCount)
    }

    /// Returns a fresh session-ready nonce.
    public func sessionReadyNonce() throws -> Data {
      try bytes(count: rappRandomByteCounts().sessionReadyNonce)
    }

    /// Returns a fresh operation identifier.
    public func operationID() throws -> Data {
      try bytes(count: rappRandomByteCounts().operationId)
    }

    /// Returns a fresh liveness challenge.
    public func livenessChallenge() throws -> Data {
      try bytes(count: rappRandomByteCounts().livenessChallenge)
    }

    private func bytes(count: UInt64) throws -> Data {
      guard count > 0, count <= UInt64(Int.max) else {
        throw RappPlatformPrimitiveError.invalidByteCount
      }
      var value = Data(count: Int(count))
      let status = value.withUnsafeMutableBytes { buffer in
        guard let address = buffer.baseAddress else { return errSecParam }
        return SecRandomCopyBytes(kSecRandomDefault, buffer.count, address)
      }
      guard status == errSecSuccess else {
        value.resetBytes(in: value.startIndex..<value.endIndex)
        throw RappPlatformPrimitiveError.entropyUnavailable
      }
      return value
    }
  }
#endif
