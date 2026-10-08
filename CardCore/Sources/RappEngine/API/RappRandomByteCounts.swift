// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// How many random bytes each generated value needs.
///
/// The engine states the sizes; the caller owns the random source.
public struct RappRandomByteCounts: Equatable, Sendable {
  /// Bytes in an offer identifier.
  public var offerId: UInt64
  /// Bytes reduced modulo the group order to sample one CPace scalar.
  public var cpaceScalarRandom: UInt64
  /// Bytes in a session-ready nonce.
  public var sessionReadyNonce: UInt64
  /// Bytes in an operation identifier.
  public var operationId: UInt64
  /// Bytes in a liveness challenge.
  public var livenessChallenge: UInt64

  /// States the size of every value the caller generates.
  public init(
    offerId: UInt64,
    cpaceScalarRandom: UInt64,
    sessionReadyNonce: UInt64,
    operationId: UInt64,
    livenessChallenge: UInt64
  ) {
    self.offerId = offerId
    self.cpaceScalarRandom = cpaceScalarRandom
    self.sessionReadyNonce = sessionReadyNonce
    self.operationId = operationId
    self.livenessChallenge = livenessChallenge
  }
}
