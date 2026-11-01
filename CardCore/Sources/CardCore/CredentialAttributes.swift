// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Parses the GET DATA PIN-container response
/// (FINEID S1 v4.2 §3.15.3 Table 19).
///
/// The container is flat, so the retries counter is found by scanning
/// for the `DF 21 04 tries ...` attributes object - the same
/// sliding-window approach the reference implementation uses; no BER
/// recursion is needed or wanted here.
public enum CredentialAttributes {
  /// The number of bytes in one attributes tag-length-value window:
  /// two tag bytes, one length byte, four attribute bytes.
  private static let attributesWindowLength: Int = 7

  /// Offset of the length byte inside the window: past the two tag
  /// bytes.
  private static let lengthOffset: Int = 2

  /// Offset of the retries byte inside the window: past the two tag
  /// bytes and the length byte.
  private static let triesOffset: Int = 3

  /// Offset of the usage-allowance byte inside the window.
  private static let usageOffset: Int = 4

  /// Offset of the unblocking-allowance byte inside the window.
  private static let unblockingOffset: Int = 5

  /// The number of bytes in one pin-changed tag-length-value window:
  /// two tag bytes, one length byte, one flag byte.
  private static let changedWindowLength: Int = 4

  /// Offset of the flag byte inside the pin-changed window.
  private static let changedFlagOffset: Int = 3

  /// How many times a credential may still be used, when the card
  /// puts a number on it.
  public static func allowances(fromResponseBody body: Data) -> CredentialAllowances? {
    let bytes = Array(body)
    guard bytes.count >= Self.attributesWindowLength else { return nil }
    for start in 0...(bytes.count - Self.attributesWindowLength) {
      guard
        bytes[start] == FineidValues.pinAttributesTagHigh,
        bytes[start + 1] == FineidValues.pinAttributesTagLow,
        bytes[start + Self.lengthOffset] == FineidValues.pinAttributesLength
      else {
        continue
      }
      return CredentialAllowances(
        usages: .usage(byte: bytes[start + Self.usageOffset]),
        unblockings: .unblocking(byte: bytes[start + Self.unblockingOffset])
      )
    }
    return nil
  }

  /// Extracts the retries-remaining counter, or nil when the body
  /// carries no parseable attributes object.
  public static func retryCounter(fromResponseBody body: Data) -> RetryCount? {
    let bytes = Array(body)
    guard bytes.count >= Self.attributesWindowLength else { return nil }
    for start in 0...(bytes.count - Self.attributesWindowLength) {
      guard
        bytes[start] == FineidValues.pinAttributesTagHigh,
        bytes[start + 1] == FineidValues.pinAttributesTagLow,
        bytes[start + Self.lengthOffset] == FineidValues.pinAttributesLength
      else {
        continue
      }
      return RetryCount(attemptsRemaining: bytes[start + Self.triesOffset])
    }
    return nil
  }

  /// Extracts the changed-since-manufacture record.
  ///
  /// The flag says whether a PIN awaits activation under both S4-1
  /// §4.6 schemes: activation sets it, by RESET RETRY COUNTER (§4.6.1)
  /// or CHANGE REFERENCE DATA (§4.6.2). An absent object or unknown
  /// flag value answers `unreadable`, never a guess
  /// (Documentation/typing-discipline.md).
  public static func pinChangeRecord(fromResponseBody body: Data) -> PinChangeRecord {
    let bytes = Array(body)
    guard bytes.count >= Self.changedWindowLength else { return .unreadable }
    for start in 0...(bytes.count - Self.changedWindowLength) {
      guard
        bytes[start] == FineidValues.pinChangedTagHigh,
        bytes[start + 1] == FineidValues.pinChangedTagLow,
        bytes[start + Self.lengthOffset] == FineidValues.pinChangedLength
      else {
        continue
      }
      switch bytes[start + Self.changedFlagOffset] {
      case FineidValues.pinChangedFlagUnchanged:
        return .unchanged

      case FineidValues.pinChangedFlagChanged:
        return .changed

      default:
        return .unreadable
      }
    }
    return .unreadable
  }
}
