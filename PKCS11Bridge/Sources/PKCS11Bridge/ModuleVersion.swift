// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CCryptoki
import Foundation

/// Which build of the bridge this is, in the one place that says so.
///
/// PKCS#11 reports a version as two bytes, and the project's version is
/// four numbers -- the date and the UTC time of day as HHMM. The two
/// fields PKCS#11 offers hold the date exactly and the time to six
/// minutes: the library reports the year and month it was cut in, and
/// the token reports the day and the six-minute step since midnight,
/// 0 to 239. A consumer that prints both reads the stamp back to the
/// step.
///
/// The token is this module's own -- a virtual token published from the
/// keychain, not the card's silicon -- so its firmware version is this
/// software's version and not a claim about anyone's hardware.
///
/// The release manager's stamp rewrites the string below and nothing else.
internal enum ModuleVersion {
  /// The stamped project version: YY.M.D.HHMM.
  internal static let text = "26.10.3.2210"

  /// Where each component of YY.M.D.HHMM sits in the stamp.
  private static let yearIndex = 0
  private static let monthIndex = 1
  private static let dayIndex = 2
  private static let timeIndex = 3

  /// HHMM is the hour times this plus the minute.
  private static let hourPlace: UInt = 100
  private static let hoursPerDay: UInt = 24
  private static let minutesPerHour: UInt = 60
  /// The firmware minor counts the time of day in steps of this many minutes.
  private static let minutesPerStep: UInt = 6

  /// Year and month, for CK_INFO.libraryVersion.
  internal static var library: CK_VERSION { library(of: text) }

  /// Day and six-minute step, for CK_TOKEN_INFO.firmwareVersion.
  internal static var firmware: CK_VERSION { firmware(of: text) }

  /// Year and month of a YY.M.D.HHMM stamp.
  internal static func library(of stamp: String) -> CK_VERSION {
    CK_VERSION(major: component(yearIndex, of: stamp), minor: component(monthIndex, of: stamp))
  }

  /// Day and six-minute step of a YY.M.D.HHMM stamp.
  internal static func firmware(of stamp: String) -> CK_VERSION {
    CK_VERSION(major: component(dayIndex, of: stamp), minor: step(of: stamp))
  }

  /// One component of the stamp, or zero when the stamp is malformed.
  ///
  /// Zero rather than a crash: a module that refuses to load because a
  /// version string was mistyped is worse than one that reports a
  /// version of zero.
  private static func component(_ index: Int, of stamp: String) -> CK_BYTE {
    guard let value = value(index, of: stamp), value <= UInt(CK_BYTE.max) else {
      return 0
    }
    return CK_BYTE(value)
  }

  /// The six-minute step since midnight of the stamp's HHMM, or zero when
  /// the stamp is malformed or names no time of day.
  private static func step(of stamp: String) -> CK_BYTE {
    guard let time = value(timeIndex, of: stamp) else {
      return 0
    }
    let hour = time / hourPlace
    let minute = time % hourPlace
    guard hour < hoursPerDay, minute < minutesPerHour else {
      return 0
    }
    return CK_BYTE((hour * minutesPerHour + minute) / minutesPerStep)
  }

  /// One component of the stamp as a number, or nil when it is missing
  /// or not a number.
  private static func value(_ index: Int, of stamp: String) -> UInt? {
    let parts = stamp.split(separator: ".")
    guard index < parts.count else {
      return nil
    }
    return UInt(parts[index])
  }
}
