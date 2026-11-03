// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The name an endpoint gives itself, as its peer shows it and stores it in the pair record (RAPP
/// v26.11.2 §4.3 items 3 and 4): 1 to ``maximumBytes`` bytes of UTF-8 holding at least one
/// character that is not white space.
///
/// A label for people: no pairing is found, matched, replaced or revoked by it.
public struct RappDisplayName: Hashable, Sendable {
  /// Most UTF-8 bytes a `display_name` or a `platform` carries (§7.1,
  /// `display_name_max_bytes`).
  public static let maximumBytes = 256

  /// The name as text.
  public let text: String

  /// The name `text`, as an endpoint sends it or its peer received it; nil
  /// when it is blank or longer than ``maximumBytes``.
  public init?(_ text: String) {
    guard Self.isLabel(text) else { return nil }
    self.text = text
  }

  /// The name `text` shortened at a character boundary until it fits in
  /// ``maximumBytes`` (§4.3 item 3); nil when it is blank.
  public init?(shortening text: String) {
    var shortened = text
    while shortened.utf8.count > Self.maximumBytes {
      shortened.removeLast()
    }
    self.init(shortened)
  }

  /// The predicate `display_name` and `platform` share (§7.1).
  internal static func isLabel(_ text: String) -> Bool {
    text.utf8.count <= maximumBytes
      && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
