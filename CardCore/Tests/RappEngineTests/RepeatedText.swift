// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A name written as one text repeated, as the corpus writes names at and
/// over the bound.
internal struct RepeatedText: Decodable {
  private enum CodingKeys: String, CodingKey {
    case text = "text"
    case count = "repeat"
  }

  private let text: String
  private let count: Int

  /// The text repeated.
  internal var expanded: String {
    String(repeating: text, count: count)
  }
}
