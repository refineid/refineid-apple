// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore
@testable import RefineIDTestHost

/// The signing time is shown once; the archive timestamp gets its own
/// row only when it does not hold.
@Suite
internal struct VerifyArchiveRowTests {
  private static let time = Date(timeIntervalSince1970: 1_800_000_000)

  /// A year, in seconds.
  private static let aYear: TimeInterval = 31_536_000

  private static let finnish = "fi"
  private static let sectigoSignerNotAfter = "2034-08-02T23:59:59Z"
  private static let sectigoCaNotAfter = "2035-10-04T00:00:00Z"
  private static let rsa3000End = "2035-01-01T00:00:00Z"
  private static let dvvFinnishRow = "Tarkastettavissa 2.8.2034 asti"
  private static let midnightEnd = "2030-01-01T00:00:00Z"
  private static let dayBefore = "31.12.2029"
  private static let documentSigningTable = "DocumentSigning"
  private static let compiledTableType = "strings"
  private static let archivalUntilKey = "verify.level.archivalUntil"

  private static func instant(_ text: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: text))
  }

  /// The Finnish row for `day`, from the table the app ships.
  private static func finnishRow(_ day: Date) throws -> String {
    let path = try #require(
      Bundle.main.path(
        forResource: Self.documentSigningTable, ofType: Self.compiledTableType, inDirectory: nil,
        forLocalization: Self.finnish))
    let data = try Data(contentsOf: URL(filePath: path))
    let table = try #require(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    let template = try #require(table[Self.archivalUntilKey])
    let date = VerifyText.dayStyle.locale(Locale(identifier: Self.finnish)).format(day)
    return String(format: template, date)
  }

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
    #expect(
      value.text?.contains(
        VerifyText.formattedDay(VerifySignatureSection.lastVerifiableDay(before: until))) == true)
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
  }

  /// Without a validity date the row claims none and carries no check.
  @Test
  internal func anUnknownValiditySaysItCouldNotBeDetermined() {
    let unknown = VerifySignatureSection.levelValue(
      .longTermArchival, validUntil: nil, now: Self.time)
    #expect(unknown.indicator != .holds)
    #expect(
      unknown.text
        == VerifyText.text(
          "verify.level.archivalUnknown", "Validity period could not be determined"))
  }

  /// DVV's maximum validity time is the last day the row shows.
  ///
  /// DVV's report for a PDF stamped by Sectigo Qualified Time Stamping
  /// Signer #3 (RSA 4096, notAfter 2034-08-02 23:59:59 UTC) under CA R35
  /// (RSA 3072, notAfter 2035-10-04): "Maximum validity time:
  /// 2034-08-02 23:59:59 (UTC)". The row reads "Tarkastettavissa
  /// 2.8.2034 asti".
  @Test
  internal func theDvvMaximumValidityTimeIsTheLastDayShown() throws {
    let signer = try Self.instant(Self.sectigoSignerNotAfter)
    let issuer = try Self.instant(Self.sectigoCaNotAfter)
    let algorithmEnd = try Self.instant(Self.rsa3000End)

    let validUntil = TimestampJudge.validUntil(
      chainEnds: [signer, issuer], suitability: .until(algorithmEnd))
    #expect(validUntil == signer)
    let day = VerifySignatureSection.lastVerifiableDay(before: signer)
    #expect(try Self.finnishRow(day) == Self.dvvFinnishRow)
  }

  /// An end at midnight UTC is already past at that instant, so the day
  /// before is the last one shown.
  @Test
  internal func aMidnightEndShowsTheDayBefore() throws {
    let midnight = try Self.instant(Self.midnightEnd)
    let day = VerifySignatureSection.lastVerifiableDay(before: midnight)
    #expect(
      VerifyText.dayStyle.locale(Locale(identifier: Self.finnish)).format(day) == Self.dayBefore)
  }

}
