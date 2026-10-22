// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RappEngine

/// Fixed values the operation drives run with, so every run is reproducible.
internal enum OperationFixture {
  internal static let operationIdentifier = identifier(OperationFill.operationIdentifier)
  internal static let otherOperation = identifier(OperationFill.otherOperation)
  internal static let digest = Data(repeating: OperationFill.digest, count: DigestLength.sha256)
  internal static let signature = Data(
    repeating: OperationFill.signature, count: OperationFill.signatureLength)
  internal static let certificate = Data(
    repeating: OperationFill.certificate, count: OperationFill.certificateLength)
  internal static let challenge = Data(
    repeating: OperationFill.challenge, count: PingChallenge.byteCount)
  internal static let origin = "https://example.test"
  internal static let documentName = "Contract.pdf"
  internal static let startMilliseconds: UInt64 = 1_000
  internal static let lifetimeMilliseconds: UInt64 = 120_000
  internal static let maximumLifetimeMilliseconds: UInt64 = 300_000
  internal static let approvalMilliseconds: UInt64 = 1_500
  /// More documents than any earlier revision allowed in one batch.
  internal static let largeBatchSize = 65

  /// An operation identifier filled with `fill`.
  internal static func identifier(_ fill: UInt8) -> RappOperationIdentifier {
    guard
      let identifier = RappOperationIdentifier(
        Data(repeating: fill, count: RappOperationIdentifier.byteCount))
    else { preconditionFailure("a filled identifier has the registered size") }
    return identifier
  }
}
