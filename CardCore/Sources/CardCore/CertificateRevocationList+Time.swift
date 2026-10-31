// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension CertificateRevocationList {
  /// Universal tag: UTCTime (RFC 5280 section 4.1.2.5.1).
  private static let tagUtcTime =
    DerValues.tagGeneralizedTime - UInt8(MemoryLayout<UInt8>.size)

  /// Standard textual encoding boundary for a PEM CRL.
  private static let pemBegin = "-----BEGIN X509 CRL-----"

  /// Standard textual encoding boundary for a PEM CRL.
  private static let pemEnd = "-----END X509 CRL-----"

  /// RFC 5280 UTCTime has twelve digits and a Z suffix.
  private static let utcTimeByteCount = 13

  /// RFC 5280 GeneralizedTime has fourteen digits and a Z suffix.
  private static let generalizedTimeByteCount = 15

  /// Number of digits in a two-digit field.
  private static let shortFieldLength = 2

  /// Number of digits in a four-digit year.
  private static let longYearLength = 4

  /// The two PEM boundary lines surrounding the Base64 body.
  private static let pemBoundaryLineCount = 2

  /// Radix of the decimal RFC 5280 time fields.
  private static let decimalRadix = 10

  /// First field after a two-digit UTCTime year.
  private static let utcMonthOffset = 2

  /// First field after a four-digit GeneralizedTime year.
  private static let generalizedMonthOffset = 4

  /// Month-to-day offset in the fixed time representation.
  private static let dayOffset = 2

  /// Month-to-hour offset in the fixed time representation.
  private static let hourOffset = 4

  /// Month-to-minute offset in the fixed time representation.
  private static let minuteOffset = 6

  /// Month-to-second offset in the fixed time representation.
  private static let secondOffset = 8

  /// RFC 5280 maps UTCTime years 50 through 99 to the twentieth century.
  private static let utcPreviousCenturyThreshold = 50

  /// Base year for UTCTime values at or above the threshold.
  private static let utcPreviousCenturyBase = 1_900

  /// Base year for UTCTime values below the threshold.
  private static let utcCurrentCenturyBase = 2_000

  /// Converts standard PEM input to DER while leaving DER input unchanged.
  internal static func derEncoded(from input: Data) throws -> Data {
    if input.first == DerValues.sequenceTagByte {
      return input
    }
    guard let text = String(data: input, encoding: .ascii) else {
      throw ValidationFailure.malformed
    }
    let lines = text.split(omittingEmptySubsequences: false) { character in
      character.isNewline
    }
    let trimmed =
      lines
      .map { line in
        line.trimmingCharacters(in: CharacterSet.whitespaces)
      }
      .filter { line in !line.isEmpty }
    guard
      trimmed.first == Self.pemBegin,
      trimmed.last == Self.pemEnd,
      trimmed.count > Self.pemBoundaryLineCount
    else {
      throw ValidationFailure.malformed
    }
    let body = trimmed.dropFirst().dropLast()
    guard
      body.allSatisfy({ !$0.hasPrefix("-----") }),
      let decoded = Data(base64Encoded: body.joined()),
      !decoded.isEmpty
    else {
      throw ValidationFailure.malformed
    }
    return decoded
  }

  /// Whether an ASN.1 identifier is one of RFC 5280's Time alternatives.
  internal static func isTimeTag(_ tag: UInt8) -> Bool {
    tag == Self.tagUtcTime || tag == DerValues.tagGeneralizedTime
  }

  /// Parses RFC 5280's exact whole-second UTC time forms.
  internal static func time(
    in encoded: Data,
    element: DerReader.Element
  ) throws -> Date {
    let content = DerReader(encoded, within: element).contentData(of: element)
    guard
      Self.isTimeTag(element.tag),
      content.last == DerValues.asciiZulu
    else {
      throw ValidationFailure.malformed
    }
    let expectedCount =
      element.tag == Self.tagUtcTime
      ? Self.utcTimeByteCount
      : Self.generalizedTimeByteCount
    guard
      content.count == expectedCount,
      content.dropLast().allSatisfy({ byte in
        byte >= DerValues.asciiZero && byte <= DerValues.asciiNine
      })
    else {
      throw ValidationFailure.malformed
    }

    return try Self.date(
      from: Self.timeFields(content, tag: element.tag)
    )
  }

  /// Extracts each fixed-position decimal field from a checked time value.
  private static func timeFields(
    _ content: Data,
    tag: UInt8
  ) throws -> TimeFields {
    let yearLength =
      tag == Self.tagUtcTime
      ? Self.shortFieldLength
      : Self.longYearLength
    let monthOffset =
      tag == Self.tagUtcTime
      ? Self.utcMonthOffset
      : Self.generalizedMonthOffset
    guard
      let encodedYear = Self.decimal(content, at: 0, length: yearLength),
      let month = Self.decimal(
        content,
        at: monthOffset,
        length: Self.shortFieldLength
      ),
      let day = Self.decimal(
        content,
        at: monthOffset + Self.dayOffset,
        length: Self.shortFieldLength
      ),
      let hour = Self.decimal(
        content,
        at: monthOffset + Self.hourOffset,
        length: Self.shortFieldLength
      ),
      let minute = Self.decimal(
        content,
        at: monthOffset + Self.minuteOffset,
        length: Self.shortFieldLength
      ),
      let second = Self.decimal(
        content,
        at: monthOffset + Self.secondOffset,
        length: Self.shortFieldLength
      )
    else {
      throw ValidationFailure.malformed
    }
    let year =
      tag == Self.tagUtcTime
      ? Self.utcYear(encodedYear)
      : encodedYear
    return TimeFields(
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      second: second
    )
  }

  /// Extracts a fixed-width decimal field from one time value.
  private static func decimal(
    _ content: Data,
    at offset: Int,
    length: Int
  ) -> Int? {
    guard
      offset >= content.startIndex,
      length > 0,
      offset + length <= content.endIndex
    else {
      return nil
    }
    return content[offset..<(offset + length)].reduce(0) { value, byte in
      value * Self.decimalRadix + Int(byte - DerValues.asciiZero)
    }
  }

  /// Expands RFC 5280's mandated 1950-to-2049 UTCTime window.
  private static func utcYear(_ encoded: Int) -> Int {
    if encoded >= Self.utcPreviousCenturyThreshold {
      return Self.utcPreviousCenturyBase + encoded
    }
    return Self.utcCurrentCenturyBase + encoded
  }

  /// Builds a strict Gregorian UTC date and rejects calendar normalization.
  private static func date(from fields: TimeFields) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
    let components = DateComponents(
      calendar: calendar,
      timeZone: calendar.timeZone,
      year: fields.year,
      month: fields.month,
      day: fields.day,
      hour: fields.hour,
      minute: fields.minute,
      second: fields.second
    )
    guard let date = calendar.date(from: components) else {
      throw ValidationFailure.malformed
    }
    let verified = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: date
    )
    guard
      verified.year == fields.year,
      verified.month == fields.month,
      verified.day == fields.day,
      verified.hour == fields.hour,
      verified.minute == fields.minute,
      verified.second == fields.second
    else {
      throw ValidationFailure.malformed
    }
    return date
  }

  /// Rejects future or expired lists at the caller's verification time.
  internal static func checkTimes(
    _ list: ParsedList,
    nextUpdate: Date,
    against currentTime: Date
  ) throws {
    guard list.thisUpdate <= currentTime else {
      throw ValidationFailure.listFromFuture
    }
    guard
      nextUpdate > list.thisUpdate,
      nextUpdate > currentTime
    else {
      throw ValidationFailure.listExpired
    }
  }
}
