// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RappEngine

/// Fixed values the harness drives both engines with.
internal enum EngineFixture {
  internal static let operationIdentifier = Data(
    repeating: EngineFill.operationIdentifier, count: EngineFill.identifierLength)
  internal static let secondOperationIdentifier = Data(
    repeating: EngineFill.secondOperationIdentifier, count: EngineFill.identifierLength)
  internal static let pairIdentifier = Data(
    repeating: EngineFill.pairIdentifier, count: EngineFill.identifierLength)
  internal static let sessionIdentifier = Data(
    repeating: EngineFill.sessionIdentifier, count: EngineFill.identifierLength)
  internal static let signature = Data(
    repeating: EngineFill.signature, count: EngineFill.signatureLength)
  internal static let digest = Data(repeating: EngineFill.digest, count: EngineFill.digestLength)
  internal static let origin = "https://example.test"
  internal static let startMilliseconds: UInt64 = 1_000
  internal static let nowMilliseconds: UInt64 = 1_500
  internal static let expiresAfterMilliseconds: UInt64 = 60_000
  internal static let maximumLifetimeMilliseconds: UInt64 = 120_000
  internal static let expiredNowMilliseconds: UInt64 = 500_000
  internal static let displayName = "Test Holder"
  internal static let personIdentifier = "010101-0101"
}
