// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// ASN.1 DER `UTCTime` and `GeneralizedTime` parsers for X.509, CRL, OCSP,
/// and RFC 3161 timestamps.
///
/// Every profile requires UTC (`Z`), ASCII decimal digits, a positive
/// Gregorian year, and a non-normalizing proleptic Gregorian calendar check so
/// out-of-range months, days, leap days, hours, minutes, or leap seconds fail
/// closed instead of rolling into an adjacent instant.
internal enum DerTime {
  /// Whole-second UTC calendar components before calendar verification.
  private struct Fields {
    /// Four-digit Gregorian year.
    let year: Int

    /// Gregorian month number.
    let month: Int

    /// Day of month.
    let day: Int

    /// Hour of day.
    let hour: Int

    /// Minute of hour.
    let minute: Int

    /// Second of minute.
    let second: Int
  }

  /// Digit width of two-digit year, month, day, hour, minute, and second fields.
  private static let shortFieldLength = 2

  /// Digit width of a four-digit GeneralizedTime year.
  private static let longYearLength = 4

  /// Fixed ASCII digit count in RFC 5280 UTCTime (`YYMMDDHHMMSS`).
  private static let utcDigitCount = 12

  /// Fixed ASCII digit count in whole-second GeneralizedTime (`YYYYMMDDHHMMSS`).
  private static let generalizedDigitCount = 14

  /// Octet count of the trailing `Z` UTC designator.
  private static let zuluSuffixLength = 1

  /// Octet count of the `.` fractional-second separator.
  private static let fractionSeparatorLength = 1

  /// Exact byte count of RFC 5280 UTCTime (`YYMMDDHHMMSSZ`).
  private static let utcTimeByteCount = Self.utcDigitCount + Self.zuluSuffixLength

  /// Exact byte count of RFC 5280 GeneralizedTime (`YYYYMMDDHHMMSSZ`).
  private static let generalizedTimeByteCount =
    Self.generalizedDigitCount + Self.zuluSuffixLength

  /// Byte offset from the month field to the day field.
  private static let dayOffset = 2

  /// Byte offset from the month field to the hour field.
  private static let hourOffset = 4

  /// Byte offset from the month field to the minute field.
  private static let minuteOffset = 6

  /// Byte offset from the month field to the second field.
  private static let secondOffset = 8

  /// Decimal radix of ASCII time components.
  private static let decimalRadix = 10

  /// Base of decimal fractional-second places.
  private static let fractionDivisor: TimeInterval = 10

  /// RFC 5280 section 4.1.2.5.1 maps UTCTime years 50..99 to 1950..1999.
  private static let utcPreviousCenturyThreshold = 50

  /// Century base for UTCTime years at or above `utcPreviousCenturyThreshold`.
  private static let utcPreviousCenturyBase = 1_900

  /// Century base for UTCTime years below `utcPreviousCenturyThreshold`.
  private static let utcCurrentCenturyBase = 2_000

  /// UTC offset from GMT in seconds.
  private static let utcOffsetSeconds = 0

  /// Whether an ASN.1 identifier octet is one of RFC 5280's `Time` choices.
  internal static func isRfc5280TimeTag(_ tag: UInt8) -> Bool {
    tag == DerValues.tagUtcTime || tag == DerValues.tagGeneralizedTime
  }

  /// Parses an RFC 5280 `Time` (`UTCTime` with 1950-2049 pivot or
  /// whole-second `GeneralizedTime`), requiring `Z` and rejecting fractions.
  internal static func rfc5280Time(
    in reader: DerReader,
    element: DerReader.Element
  ) -> Date? {
    Self.rfc5280Time(tag: element.tag, content: reader.contentData(of: element))
  }

  /// Parses RFC 5280 `Time` content octets for `tag`, rebasing slices safely.
  internal static func rfc5280Time(tag: UInt8, content: Data) -> Date? {
    switch tag {
    case DerValues.tagUtcTime:
      Self.rfc5280UtcTime(content)

    case DerValues.tagGeneralizedTime:
      Self.rfc5280GeneralizedTime(content)

    default:
      nil
    }
  }

  /// Parses an RFC 5280 / RFC 6960 whole-second `GeneralizedTime`
  /// (`YYYYMMDDHHMMSSZ`), rejecting `UTCTime` and fractional seconds.
  internal static func rfc5280GeneralizedTime(
    in reader: DerReader,
    element: DerReader.Element
  ) -> Date? {
    guard element.tag == DerValues.tagGeneralizedTime else { return nil }
    return Self.rfc5280GeneralizedTime(reader.contentData(of: element))
  }

  /// Parses RFC 5280 / RFC 6960 whole-second `GeneralizedTime` content octets
  /// (`YYYYMMDDHHMMSSZ`), rejecting fractional seconds.
  internal static func rfc5280GeneralizedTime(_ content: Data) -> Date? {
    let bytes = Self.zeroBased(content)
    guard
      bytes.count == Self.generalizedTimeByteCount,
      bytes.last == DerValues.asciiZulu,
      let fields = Self.fields(in: bytes, yearLength: Self.longYearLength)
    else {
      return nil
    }
    return Self.utcDate(from: fields)
  }

  /// Parses an RFC 3161 `GeneralizedTime` element (`YYYYMMDDHHMMSS[.s...]Z`).
  internal static func rfc3161GeneralizedTime(
    in reader: DerReader,
    element: DerReader.Element
  ) -> Date? {
    guard element.tag == DerValues.tagGeneralizedTime else { return nil }
    return Self.rfc3161GeneralizedTime(reader.contentData(of: element))
  }

  /// Parses RFC 3161 `GeneralizedTime` content octets (`YYYYMMDDHHMMSS[.s...]Z`).
  internal static func rfc3161GeneralizedTime(_ content: Data) -> Date? {
    let bytes = Self.zeroBased(content)
    guard
      bytes.count >= Self.generalizedTimeByteCount,
      bytes.last == DerValues.asciiZulu,
      let fields = Self.fields(in: bytes, yearLength: Self.longYearLength),
      let date = Self.utcDate(from: fields),
      let fraction = Self.fractionalSeconds(in: bytes)
    else {
      return nil
    }
    return fraction == 0 ? date : date.addingTimeInterval(fraction)
  }

  /// Parses RFC 5280 `UTCTime` content octets (`YYMMDDHHMMSSZ`).
  private static func rfc5280UtcTime(_ content: Data) -> Date? {
    let bytes = Self.zeroBased(content)
    guard
      bytes.count == Self.utcTimeByteCount,
      bytes.last == DerValues.asciiZulu,
      let fields = Self.fields(in: bytes, yearLength: Self.shortFieldLength)
    else {
      return nil
    }
    return Self.utcDate(from: fields)
  }

  /// Rebases sliced `Data` to zero-based indices before fixed-offset indexing.
  private static func zeroBased(_ content: Data) -> Data {
    content.startIndex == 0 ? content : Data(content)
  }

  /// Extracts fixed-width decimal calendar fields from zero-based time octets.
  private static func fields(in bytes: Data, yearLength: Int) -> Fields? {
    let monthOffset = yearLength
    guard
      bytes.count >= monthOffset + Self.secondOffset + Self.shortFieldLength,
      let encodedYear = Self.decimal(bytes[0..<yearLength]),
      let month = Self.twoDigitField(in: bytes, at: monthOffset),
      let day = Self.twoDigitField(in: bytes, at: monthOffset + Self.dayOffset),
      let hour = Self.twoDigitField(in: bytes, at: monthOffset + Self.hourOffset),
      let minute = Self.twoDigitField(in: bytes, at: monthOffset + Self.minuteOffset),
      let second = Self.twoDigitField(in: bytes, at: monthOffset + Self.secondOffset)
    else {
      return nil
    }
    let year =
      yearLength == Self.shortFieldLength
      ? Self.utcYear(encodedYear)
      : encodedYear
    guard year > 0 else { return nil }
    return Fields(
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      second: second
    )
  }

  /// Reads one two-digit ASCII decimal field at `offset`.
  private static func twoDigitField(in bytes: Data, at offset: Int) -> Int? {
    Self.decimal(bytes[offset..<(offset + Self.shortFieldLength)])
  }

  /// Expands RFC 5280's mandated 1950-to-2049 UTCTime window.
  private static func utcYear(_ encoded: Int) -> Int {
    encoded >= Self.utcPreviousCenturyThreshold
      ? Self.utcPreviousCenturyBase + encoded
      : Self.utcCurrentCenturyBase + encoded
  }

  /// Parses the optional RFC 3161 fractional-second suffix (`.s...` before `Z`).
  private static func fractionalSeconds(in bytes: Data) -> TimeInterval? {
    guard bytes.count > Self.generalizedTimeByteCount else { return 0 }
    let separatorIndex = Self.generalizedDigitCount
    guard bytes[separatorIndex] == DerValues.asciiPeriod else { return nil }
    let fractionStart = separatorIndex + Self.fractionSeparatorLength
    let digits = bytes[fractionStart..<(bytes.count - Self.zuluSuffixLength)]
    guard let numerator = Self.decimal(digits) else {
      return nil
    }
    return TimeInterval(numerator) / pow(Self.fractionDivisor, TimeInterval(digits.count))
  }

  /// Parses a non-empty slice of ASCII decimal digits with overflow checking.
  private static func decimal(_ digits: Data) -> Int? {
    guard !digits.isEmpty else { return nil }
    var value = 0
    for byte in digits {
      guard byte >= DerValues.asciiZero, byte <= DerValues.asciiNine else {
        return nil
      }
      let digit = Int(byte - DerValues.asciiZero)
      guard value <= (Int.max - digit) / Self.decimalRadix else {
        return nil
      }
      value = value * Self.decimalRadix + digit
    }
    return value
  }

  /// Builds a UTC Gregorian date and rejects values Calendar would normalize.
  private static func utcDate(from fields: Fields) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: Self.utcOffsetSeconds) ?? .gmt
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
    guard let date = calendar.date(from: components) else { return nil }
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
      return nil
    }
    return date
  }
}
