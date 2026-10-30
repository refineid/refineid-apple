// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The complete serial the chip reports in its PKCS#15 token-info file.
///
/// This is the identity every security binding uses: PIN 1 memory and
/// rejected-PIN memory bind to this full value and never to the short
/// ``PrintedSerial``, which is not an identity.
/// The value never appears in logs.
public struct ChipSerial: Codable, Equatable, Hashable, Sendable {
  /// A real serial is short; anything longer is a parser or transport
  /// fault refused at construction.
  public static let maximumLength: Int = 64

  /// First printable ASCII byte (the space is deliberately excluded).
  private static let printableMinimum: UInt8 = 33

  /// Last printable ASCII byte.
  private static let printableMaximum: UInt8 = 126

  /// The full serial value.
  public let value: String

  /// Refuses empty, oversized, and non-printable-ASCII values.
  public init?(value: String) {
    let bytes = Array(value.utf8)
    guard !bytes.isEmpty, bytes.count <= Self.maximumLength else { return nil }
    guard
      bytes.allSatisfy({ byte in
        byte >= Self.printableMinimum && byte <= Self.printableMaximum
      })
    else {
      return nil
    }
    self.value = value
  }

  /// Decodes a stored serial through the same checks as ``init(value:)``;
  /// a malformed value fails decoding.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let serial = Self(value: text) else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Not a chip serial")
    }
    self = serial
  }

  /// Encodes the serial as its single string value.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}
