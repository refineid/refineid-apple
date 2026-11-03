// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One envelope carrying a name.
internal struct DisplayNameVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case name = "name"
    case message = "message"
    case displayName = "display_name"
    case expected = "expected"
    case recordNameBefore = "record_name_before"
    case recordNameAfter = "record_name_after"
    case recordRewritten = "record_rewritten"
    case envelopeHex = "envelope_cbor_hex"
  }

  internal static let accepted = "accepted"

  internal let name: String
  internal let message: String?
  /// The name the envelope carries; nil when it carries none.
  internal let displayName: String?
  internal let expected: String
  internal let recordNameBefore: String?
  internal let recordNameAfter: String?
  /// Whether accepting the name rewrites the record; false when the
  /// vector says nothing.
  internal let recordRewritten: Bool
  internal let envelopeHex: String

  internal init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    message = try container.decodeIfPresent(String.self, forKey: .message)
    if let text = try? container.decodeIfPresent(String.self, forKey: .displayName) {
      displayName = text
    } else if let repeated = try? container.decodeIfPresent(RepeatedText.self, forKey: .displayName)
    {
      displayName = repeated.expanded
    } else {
      displayName = nil
    }
    expected = try container.decode(String.self, forKey: .expected)
    recordNameBefore = try container.decodeIfPresent(String.self, forKey: .recordNameBefore)
    recordNameAfter = try container.decodeIfPresent(String.self, forKey: .recordNameAfter)
    recordRewritten =
      try container.decodeIfPresent(Bool.self, forKey: .recordRewritten) ?? false
    envelopeHex = try container.decode(String.self, forKey: .envelopeHex)
  }
}
