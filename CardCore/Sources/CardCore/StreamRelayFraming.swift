// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The `fi.refineid.stream` frame contract.
///
/// Every frame is a 2-byte big-endian length prefix followed by exactly that
/// many payload bytes. A declared length of zero is malformed, and the
/// 16-bit prefix bounds every allocation.
public enum StreamRelayFraming {
  /// Byte count of the big-endian length prefix.
  public static let lengthPrefixByteCount = 2

  /// Largest payload the 16-bit prefix can express.
  public static let maximumPayloadByteCount = Int(UInt16.max)

  /// Bit width of one length-prefix byte.
  private static let bitsPerPrefixByte = 8

  /// Wraps one payload in the length-prefixed wire form, or nil when the
  /// payload is empty or exceeds the prefix range.
  public static func encode(_ payload: Data) -> Data? {
    guard payload.count >= 1, payload.count <= maximumPayloadByteCount else {
      return nil
    }
    var length = UInt16(payload.count).bigEndian
    var framed = withUnsafeBytes(of: &length) { Data($0) }
    framed.append(payload)
    return framed
  }

  /// Reads the declared payload length from one complete prefix, or nil
  /// when the prefix is incomplete or declares the malformed zero length.
  public static func payloadByteCount(lengthPrefix: Data) -> Int? {
    guard lengthPrefix.count == lengthPrefixByteCount else { return nil }
    let length = lengthPrefix.reduce(into: 0) { partial, byte in
      partial = partial << bitsPerPrefixByte | Int(byte)
    }
    guard length >= 1 else { return nil }
    return length
  }
}
