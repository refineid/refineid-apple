// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// Direct unit tests for the unified `DerTime` ASN.1 time parsers.
@Suite
internal struct DerTimeTests {
  /// Unix timestamp for `1950-01-01T00:00:00Z`.
  private static let startOf1950: TimeInterval = -631_152_000

  /// Unix timestamp for `1999-12-31T23:59:59Z`.
  private static let endOf1999: TimeInterval = 946_684_799

  /// Unix timestamp for `2000-01-01T00:00:00Z`.
  private static let startOf2000: TimeInterval = 946_684_800

  /// Unix timestamp for `2000-02-29T00:00:00Z`.
  private static let leapDay2000: TimeInterval = 951_782_400

  /// Unix timestamp for `2024-02-29T12:34:56Z`.
  private static let leapDay2024: TimeInterval = 1_709_210_096

  /// Unix timestamp for `2026-08-04T07:46:33Z`.
  internal static let sampleInstant: TimeInterval = 1_785_829_593

  /// Unix timestamp for `2049-12-31T23:59:59Z`.
  private static let endOf2049: TimeInterval = 2_524_607_999

  /// Unix timestamp for `2050-01-01T00:00:00Z`.
  private static let startOf2050: TimeInterval = 2_524_608_000

  /// Half of a second (`0.5`).
  private static let halfSecond: TimeInterval = 0.5

  /// One eighth of a second (`0.125`).
  internal static let eighthSecond: TimeInterval = 0.125

  /// Five milliseconds (`0.005`).
  private static let fiveMilliseconds: TimeInterval = 0.005

  /// Digit count guaranteed to overflow a 64-bit signed integer.
  private static let overflowDigitCount = 128

  /// Parses a synthetic TLV with `DerTime.rfc5280Time`.
  internal static func parseRfc5280Time(tag: UInt8, _ text: String) -> Date? {
    let encoded = DerEncoder.tlv(tag, Data(text.utf8))
    var reader = DerReader(encoded)
    guard let element = reader.next() else { return nil }
    return DerTime.rfc5280Time(in: reader, element: element)
  }

  /// Parses a synthetic TLV with `DerTime.rfc5280GeneralizedTime`.
  internal static func parseRfc5280GeneralizedTime(tag: UInt8, _ text: String) -> Date? {
    let encoded = DerEncoder.tlv(tag, Data(text.utf8))
    var reader = DerReader(encoded)
    guard let element = reader.next() else { return nil }
    return DerTime.rfc5280GeneralizedTime(in: reader, element: element)
  }

  /// Parses a synthetic TLV with `DerTime.rfc3161GeneralizedTime(in:element:)`.
  private static func parseRfc3161Element(tag: UInt8, _ text: String) -> Date? {
    let encoded = DerEncoder.tlv(tag, Data(text.utf8))
    var reader = DerReader(encoded)
    guard let element = reader.next() else { return nil }
    return DerTime.rfc3161GeneralizedTime(in: reader, element: element)
  }

  @Test
  internal func rfc5280TimeTagPredicateMatchesOnlyUtcAndGeneralizedTime() {
    #expect(DerTime.isRfc5280TimeTag(DerValues.tagUtcTime))
    #expect(DerTime.isRfc5280TimeTag(DerValues.tagGeneralizedTime))
    #expect(!DerTime.isRfc5280TimeTag(DerValues.tagIa5String))
    #expect(!DerTime.isRfc5280TimeTag(DerValues.tagUtf8String))
    #expect(!DerTime.isRfc5280TimeTag(DerValues.tagSequence))
  }

  @Test
  internal func utcTimeMapsThe1950Through2049PivotBoundaries() {
    #expect(
      Self.parseRfc5280Time(tag: DerValues.tagUtcTime, "500101000000Z")
        == Date(timeIntervalSince1970: Self.startOf1950)
    )
    #expect(
      Self.parseRfc5280Time(tag: DerValues.tagUtcTime, "991231235959Z")
        == Date(timeIntervalSince1970: Self.endOf1999)
    )
    #expect(
      Self.parseRfc5280Time(tag: DerValues.tagUtcTime, "000101000000Z")
        == Date(timeIntervalSince1970: Self.startOf2000)
    )
    #expect(
      Self.parseRfc5280Time(tag: DerValues.tagUtcTime, "491231235959Z")
        == Date(timeIntervalSince1970: Self.endOf2049)
    )
  }

  @Test
  internal func generalizedTimeAcceptsValidLeapDaysAndPost2049Dates() {
    let leap2000 = Date(timeIntervalSince1970: Self.leapDay2000)
    let leap2024 = Date(timeIntervalSince1970: Self.leapDay2024)
    let year2050 = Date(timeIntervalSince1970: Self.startOf2050)

    #expect(Self.parseRfc5280Time(tag: DerValues.tagUtcTime, "000229000000Z") == leap2000)
    #expect(
      Self.parseRfc5280GeneralizedTime(tag: DerValues.tagGeneralizedTime, "20000229000000Z")
        == leap2000
    )
    #expect(
      Self.parseRfc5280GeneralizedTime(tag: DerValues.tagGeneralizedTime, "20240229123456Z")
        == leap2024
    )
    #expect(
      Self.parseRfc5280Time(tag: DerValues.tagGeneralizedTime, "20500101000000Z")
        == year2050
    )
    #expect(DerTime.rfc3161GeneralizedTime(Data("20240229123456Z".utf8)) == leap2024)
  }

  @Test
  internal func invalidGregorianCalendarComponentsAreRejectedWithoutNormalization() {
    let invalidGeneralized = [
      "00000101000000Z",
      "19000229000000Z",
      "20260229000000Z",
      "20260001000000Z",
      "20261301000000Z",
      "20260100000000Z",
      "20260431000000Z",
      "20260101240000Z",
      "20260101006000Z",
      "20260101235960Z",
    ]
    for text in invalidGeneralized {
      #expect(
        Self.parseRfc5280GeneralizedTime(tag: DerValues.tagGeneralizedTime, text) == nil,
        "\(text) was accepted by rfc5280GeneralizedTime"
      )
      #expect(
        Self.parseRfc5280Time(tag: DerValues.tagGeneralizedTime, text) == nil,
        "\(text) was accepted by rfc5280Time"
      )
      #expect(
        DerTime.rfc3161GeneralizedTime(Data(text.utf8)) == nil,
        "\(text) was accepted by rfc3161GeneralizedTime"
      )
    }

    let invalidUtc = [
      "260229000000Z",
      "260001000000Z",
      "261301000000Z",
      "260100000000Z",
      "260431000000Z",
      "260101240000Z",
      "260101006000Z",
      "260101235960Z",
    ]
    for text in invalidUtc {
      #expect(
        Self.parseRfc5280Time(tag: DerValues.tagUtcTime, text) == nil,
        "\(text) was accepted as UTCTime"
      )
    }
  }

  @Test
  internal func rfc5280ProfilesRejectFractionalSecondsAndWrongTags() {
    #expect(
      Self.parseRfc5280GeneralizedTime(
        tag: DerValues.tagGeneralizedTime,
        "20260804074633.5Z"
      ) == nil
    )
    #expect(
      Self.parseRfc5280Time(
        tag: DerValues.tagGeneralizedTime,
        "20260804074633.125Z"
      ) == nil
    )
    #expect(
      Self.parseRfc5280Time(tag: DerValues.tagUtcTime, "260804074633.5Z") == nil
    )
    #expect(
      Self.parseRfc5280GeneralizedTime(tag: DerValues.tagUtcTime, "260804074633Z") == nil
    )
    #expect(
      Self.parseRfc5280Time(tag: DerValues.tagIa5String, "20260804074633Z") == nil
    )
  }

  @Test
  internal func rfc3161GeneralizedTimeParsesFractionalSecondsAndRejectsMalformedOnes() {
    let base = Date(timeIntervalSince1970: Self.sampleInstant)
    #expect(DerTime.rfc3161GeneralizedTime(Data("20260804074633Z".utf8)) == base)
    #expect(DerTime.rfc3161GeneralizedTime(Data("20260804074633.0Z".utf8)) == base)
    #expect(DerTime.rfc3161GeneralizedTime(Data("20260804074633.000Z".utf8)) == base)
    #expect(
      Self.parseRfc3161Element(tag: DerValues.tagGeneralizedTime, "20260804074633.5Z")
        == base.addingTimeInterval(Self.halfSecond)
    )
    #expect(
      DerTime.rfc3161GeneralizedTime(Data("20260804074633.500Z".utf8))
        == base.addingTimeInterval(Self.halfSecond)
    )
    #expect(
      DerTime.rfc3161GeneralizedTime(Data("20260804074633.125Z".utf8))
        == base.addingTimeInterval(Self.eighthSecond)
    )
    #expect(
      DerTime.rfc3161GeneralizedTime(Data("20260804074633.1250Z".utf8))
        == base.addingTimeInterval(Self.eighthSecond)
    )
    #expect(
      DerTime.rfc3161GeneralizedTime(Data("20260804074633.005Z".utf8))
        == base.addingTimeInterval(Self.fiveMilliseconds)
    )
    #expect(
      Self.parseRfc3161Element(tag: DerValues.tagUtcTime, "260804074633Z") == nil
    )

    let malformedFractions = [
      "20260804074633.Z",
      "20260804074633,5Z",
      "20260804074633..5Z",
      "20260804074633.5aZ",
      "20260804074633." + String(repeating: "9", count: Self.overflowDigitCount) + "Z",
    ]
    for text in malformedFractions {
      #expect(
        DerTime.rfc3161GeneralizedTime(Data(text.utf8)) == nil,
        "\(text) was accepted by rfc3161GeneralizedTime"
      )
    }
  }
}
