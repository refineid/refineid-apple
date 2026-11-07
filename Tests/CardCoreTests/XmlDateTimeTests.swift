// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// The `xsd:dateTime` reader.
@Suite
internal struct XmlDateTimeTests {
  /// 2016-07-01T00:00:00Z as a Unix time.
  private static let regimeEnd: TimeInterval = 1_467_331_200

  /// Seconds in an hour.
  private static let hour: TimeInterval = 3_600

  @Test
  internal func utcFractionsAndOffsetsRead() {
    let expected = Date(timeIntervalSince1970: Self.regimeEnd)
    #expect(XmlDateTime.instant("2016-07-01T00:00:00Z") == expected)
    #expect(XmlDateTime.instant(" 2016-07-01T00:00:00.123Z\n") == expected)
    #expect(XmlDateTime.instant("2016-07-01T00:00:00") == expected)
    #expect(XmlDateTime.instant("2016-07-01T02:00:00+02:00") == expected)
    #expect(XmlDateTime.instant("2016-06-30T23:00:00-01:00") == expected)
    #expect(XmlDateTime.instant("2016-07-01T01:00:00Z") == expected.addingTimeInterval(Self.hour))
  }

  @Test
  internal func malformedValuesAreRefused() {
    for text in [
      "", "2016-07-01", "2016-07-01 00:00:00Z", "2016-13-01T00:00:00Z", "2016-02-30T00:00:00Z",
      "2016-07-01T24:00:00Z", "2016-07-01T00:00:00+15:00", "2016-07-01T00:00:00+02:60",
      "16-07-01T00:00:00Z",
    ] {
      #expect(XmlDateTime.instant(text) == nil, "\(text) was read")
    }
  }
}
