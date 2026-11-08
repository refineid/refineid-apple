// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

@testable import RefineIDTestHost

/// The signing time is shown once; the archive timestamp gets its own
/// row only when it does not hold.
@Suite
internal struct VerifyArchiveRowTests {
  private static let time = Date(timeIntervalSince1970: 1_800_000_000)

  @Test
  internal func aHoldingArchiveTimestampHasNoRow() {
    #expect(!VerifySignatureSection.showsArchiveRow([]))
    #expect(!VerifySignatureSection.showsArchiveRow([.anchored(Self.time)]))
  }

  @Test
  internal func anUnprovenOrFailedArchiveTimestampIsShown() {
    #expect(VerifySignatureSection.showsArchiveRow([.claimed(Self.time)]))
    #expect(VerifySignatureSection.showsArchiveRow([.invalid]))
  }
}
