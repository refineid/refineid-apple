// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RefineIDTestHost

/// The signer name shown on the verification screen.
@Suite
internal struct DisplayedSignerNameTests {
  /// A synthetic commonName.
  private static let name = "SIGNER TEST 000000000"

  /// The right-to-left override (Unicode Cf).
  private static let rightToLeftOverride = "\u{202E}"

  /// A line feed (Unicode Cc).
  private static let lineFeed = "\n"

  @Test
  internal func controlAndBidiFormatCharactersAreLeftOut() {
    let carried = Self.rightToLeftOverride + Self.name + Self.lineFeed
    #expect(DisplayedSignerName.text(of: carried) == Self.name)
    #expect(DisplayedSignerName.text(of: Self.name) == Self.name)
  }
}
