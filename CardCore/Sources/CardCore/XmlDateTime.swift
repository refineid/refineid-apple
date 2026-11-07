// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Reads an `xsd:dateTime` (XML Schema Part 2 section 3.2.7), the time
/// type of every instant a trusted list states.
internal enum XmlDateTime {
  /// The shape `YYYY-MM-DDThh:mm:ss`, with optional fractional seconds
  /// and an optional zone, `Z` or `+hh:mm`; a value without a zone is
  /// read as UTC.
  private static let pattern =
    #"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?"#
    + #"(Z|[+-]\d{2}:\d{2})?$"#

  /// The captures after the date fields: the zone.
  private static let trailingCaptures = 1

  /// The UTC designator.
  private static let utcDesignator = "Z"

  /// The sign of an offset west of UTC.
  private static let westSign = "-"

  /// Minutes in an hour.
  private static let minutesPerHour = 60

  /// Seconds in a minute.
  private static let secondsPerMinute = 60

  /// The largest offset's hours (XML Schema Part 2 section 3.2.7.3:
  /// `14:00`).
  private static let maximumOffsetHours = 14

  /// The proleptic Gregorian calendar in UTC.
  private static let calendar: Calendar = {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return gregorian
  }()

  /// The date fields `pattern` captures, in capture order.
  private static var fields: [WritableKeyPath<DateComponents, Int?>] {
    [\.year, \.month, \.day, \.hour, \.minute, \.second]
  }

  /// The instant `text` names, nil for anything that is not a
  /// well-formed `dateTime` or does not name a real date.
  internal static func instant(_ text: String) -> Date? {
    let trimmed = XadesXmlParser.trimmed(text)
    guard
      let expression = try? NSRegularExpression(pattern: Self.pattern),
      let match = expression.firstMatch(
        in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
      match.numberOfRanges == Self.fields.count + Self.trailingCaptures + 1
    else {
      return nil
    }
    func capture(_ index: Int) -> String? {
      Range(match.range(at: index), in: trimmed).map { range in String(trimmed[range]) }
    }
    var components = DateComponents()
    for (offset, field) in Self.fields.enumerated() {
      guard let value = capture(offset + 1).flatMap({ text in Int(text) }) else { return nil }
      components[keyPath: field] = value
    }
    guard
      let offset = Self.offset(capture(Self.fields.count + 1)),
      let date = Self.calendar.date(from: components),
      Self.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        == components
    else {
      return nil
    }
    return date.addingTimeInterval(-offset)
  }

  /// The offset east of UTC a zone designator names, in seconds; zero
  /// for `Z` and for none, nil for a malformed designator.
  private static func offset(_ designator: String?) -> TimeInterval? {
    guard let designator, designator != Self.utcDesignator else { return 0 }
    let sign: TimeInterval = designator.hasPrefix(Self.westSign) ? -1 : 1
    let parts = designator.dropFirst().split(separator: ":").compactMap { part in Int(part) }
    guard
      parts.count == XmlValues.qualifiedNameParts,
      let hours = parts.first, let minutes = parts.last,
      minutes < Self.minutesPerHour,
      hours * Self.minutesPerHour + minutes <= Self.maximumOffsetHours * Self.minutesPerHour
    else {
      return nil
    }
    let seconds = (hours * Self.minutesPerHour + minutes) * Self.secondsPerMinute
    return sign * TimeInterval(seconds)
  }
}
