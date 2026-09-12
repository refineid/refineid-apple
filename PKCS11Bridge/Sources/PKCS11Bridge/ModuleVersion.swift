// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CCryptoki
import Foundation

/// Which build of the bridge this is, in the one place that says so.
///
/// PKCS#11 reports a version as two bytes, and the project's version is
/// four numbers -- the date and the ten-minute bucket. The two fields
/// PKCS#11 offers hold it exactly: the library reports the year and
/// month it was cut in, and the token reports the day and the bucket.
/// A consumer that prints both reads the whole stamp back.
///
/// The token is this module's own -- a virtual token published from the
/// keychain, not the card's silicon -- so its firmware version is this
/// software's version and not a claim about anyone's hardware.
///
/// Scripts/stamp-version.sh rewrites the string below and nothing else.
internal enum ModuleVersion {
  /// The stamped project version: YY.M.D.BUCKET.
  internal static let text = "26.9.12.202"

  /// Where each component of YY.M.D.BUCKET sits in the stamp.
  private static let yearIndex = 0
  private static let monthIndex = 1
  private static let dayIndex = 2
  private static let bucketIndex = 3

  /// Year and month, for CK_INFO.libraryVersion.
  internal static var library: CK_VERSION {
    CK_VERSION(major: component(yearIndex), minor: component(monthIndex))
  }

  /// Day and ten-minute bucket, for CK_TOKEN_INFO.firmwareVersion.
  internal static var firmware: CK_VERSION {
    CK_VERSION(major: component(dayIndex), minor: component(bucketIndex))
  }

  /// One component of the stamp, or zero when the stamp is malformed.
  ///
  /// Zero rather than a crash: a module that refuses to load because a
  /// version string was mistyped is worse than one that reports a
  /// version of zero.
  private static func component(_ index: Int) -> CK_BYTE {
    let parts = text.split(separator: ".")
    guard index < parts.count, let value = UInt(parts[index]), value <= UInt(CK_BYTE.max) else {
      return 0
    }
    return CK_BYTE(value)
  }
}
