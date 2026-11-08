// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Until when a signature algorithm and key size stay acceptable, as EU
/// DSS judges them, so this app and DSS (and DVV's validator, which runs
/// it) give the same date.
///
/// Source: EU DSS 6.5.1, `policy/constraint.xml` inside
/// `dss-policy-jaxb-6.5.1.jar` (SHA-256 of the jar
/// a7b6190222f8ed018c4e7305469d26c091a23c635e34b0af611205bf83ae4a71, as
/// pinned in `Scripts/dss-gate/dss.lock`; of the file
/// 34b09d3837426997f07dc6c9c7c637d0dea482839c0f652f2c016abd6e685a75),
/// element `Cryptographic/AlgoExpirationDate`, which cites ETSI TS 119
/// 312 V2.1.1. Only the rows for keys and digests a timestamp this
/// verifier accepts can carry are kept: RSA, ECDSA, and SHA-256, SHA-384
/// and SHA-512.
///
/// DSS reads the table as `CryptographicSuiteUtils.getExpirationDate`
/// does: a row applies when the key is at least its size; when any
/// applicable row has no date the algorithm does not expire, otherwise
/// the latest applicable date ends it. A key smaller than every row is
/// not acceptable at all. The digest's own date ends it too when
/// earlier.
internal enum CryptographicSuitability {
  /// What the table says about one algorithm and key.
  internal enum Verdict: Equatable {
    /// Not acceptable at any time.
    case unacceptable

    /// Acceptable with no end date.
    case unlimited

    /// Acceptable before this instant.
    case until(Date)
  }

  /// A signature key's family and size.
  internal struct Key: Equatable {
    internal let family: Family
    internal let bits: Int

    /// The key of an accepted certificate, nil for another family.
    internal init?(_ key: SecKey) {
      guard
        let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
        let type = attributes[kSecAttrKeyType] as? String,
        let size = attributes[kSecAttrKeySizeInBits] as? Int
      else {
        return nil
      }
      if type == kSecAttrKeyTypeRSA as String {
        family = .rsa
      } else if type == kSecAttrKeyTypeECSECPrimeRandom as String {
        family = .ecdsa
      } else {
        return nil
      }
      bits = size
    }

    internal init(family: Family, bits: Int) {
      self.family = family
      self.bits = bits
    }
  }

  /// The key families the table covers.
  internal enum Family: Equatable {
    case ecdsa
    case rsa
  }

  /// One `Algo` row: the smallest key it covers and its date, nil for
  /// one without a date.
  private struct Row {
    let family: Family
    let bits: Int
    let until: String?
  }

  /// The `Size` attributes of the RSA and ECDSA rows, in bits.
  private enum Size {
    static let rsa786 = 786
    static let rsa1024 = 1_024
    static let rsa1536 = 1_536
    static let rsa1900 = 1_900
    static let rsa3000 = 3_000
    static let ecdsa160 = 160
    static let ecdsa163 = 163
    static let ecdsa224 = 224
    static let ecdsa256 = 256
  }

  /// `AlgoExpirationDate Format`.
  private static let dateFormat = "yyyy-MM-dd"

  /// The locale that reads `dateFormat` literally.
  private static let posixLocale = "en_US_POSIX"

  /// DSS reads each date as midnight in this zone.
  private static let dateZone = "UTC"

  /// The RSA and ECDSA rows of `AlgoExpirationDate`, as written there.
  private static let rows: [Row] = [
    Row(family: .rsa, bits: Size.rsa786, until: "2010-08-01"),
    Row(family: .rsa, bits: Size.rsa1024, until: "2019-10-01"),
    Row(family: .rsa, bits: Size.rsa1536, until: "2019-10-01"),
    Row(family: .rsa, bits: Size.rsa1900, until: "2027-01-01"),
    Row(family: .rsa, bits: Size.rsa3000, until: "2035-01-01"),
    Row(family: .ecdsa, bits: Size.ecdsa160, until: "2012-08-01"),
    Row(family: .ecdsa, bits: Size.ecdsa163, until: "2012-08-01"),
    Row(family: .ecdsa, bits: Size.ecdsa224, until: "2021-10-01"),
    Row(family: .ecdsa, bits: Size.ecdsa256, until: nil),
  ]

  /// The digest rows: SHA-256, SHA-384 and SHA-512 carry no date.
  private static func digestUntil(_ digest: TimestampCmsVerifier.Digest) -> String? {
    switch digest {
    case .sha256, .sha384, .sha512:
      nil
    }
  }

  /// The table's dates, read as midnight UTC as DSS reads them.
  private static func date(_ text: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: Self.posixLocale)
    formatter.timeZone = TimeZone(identifier: Self.dateZone)
    formatter.dateFormat = Self.dateFormat
    return formatter.date(from: text)
  }

  /// Until when `key` signing over `digest` stays acceptable.
  internal static func verdict(
    for key: Key,
    digest: TimestampCmsVerifier.Digest
  ) -> Verdict {
    let applicable = Self.rows.filter { row in row.family == key.family && key.bits >= row.bits }
    guard !applicable.isEmpty else { return .unacceptable }
    var ends: [Date] = []
    if !applicable.contains(where: { row in row.until == nil }) {
      guard let latest = applicable.compactMap({ row in row.until.flatMap(Self.date) }).max()
      else {
        return .unacceptable
      }
      ends.append(latest)
    }
    if let digestEnd = Self.digestUntil(digest).flatMap(Self.date) {
      ends.append(digestEnd)
    }
    return ends.min().map(Verdict.until) ?? .unlimited
  }
}
