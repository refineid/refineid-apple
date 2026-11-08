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

  /// A year, in seconds.
  private static let aYear: TimeInterval = 31_536_000

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

  /// Before its validity ends, the archival level says until when it
  /// can be verified, with the check.
  @Test
  internal func anArchivalSignatureSaysUntilWhenItCanBeVerified() {
    let until = Self.time.addingTimeInterval(Self.aYear)
    let value = VerifySignatureSection.levelValue(
      .longTermArchival, validUntil: until, now: Self.time)
    #expect(value.indicator == .holds)
    #expect(value.text?.contains(VerifyText.formattedDay(until)) == true)
  }

  /// Once its validity has ended, it needs a new archive timestamp and
  /// carries no check.
  @Test
  internal func aPastValidityNeedsANewArchiveTimestamp() {
    let ended = Self.time.addingTimeInterval(-Self.aYear)
    let value = VerifySignatureSection.levelValue(
      .longTermArchival, validUntil: ended, now: Self.time)
    #expect(value.indicator != .holds)
    #expect(
      value.text == VerifyText.text("verify.level.archivalExpired", "Needs a new archive timestamp")
    )
    let unknown = VerifySignatureSection.levelValue(
      .longTermArchival, validUntil: nil, now: Self.time)
    #expect(unknown.text == value.text)
  }
}
