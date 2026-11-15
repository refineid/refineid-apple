// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The time-stamp authority signatures ask, configured or shipped.
///
/// One service: whoever configures one answers for it, and every token
/// it returns is still verified before it is trusted. The address is
/// configuration, not a secret: it names a public service and lives in
/// preferences, written on macOS by the Time Stamp settings pane and on
/// iOS by the Settings app. Nothing usable stored means the shipped
/// qualified service.
internal enum TimestampAuthorityStore: Sendable {
  /// The last Test verdict: what was probed, when, and whether a
  /// verified token came back.
  internal struct Verification: Equatable, Sendable {
    /// The request address that was probed, scheme included.
    internal let address: String

    /// When the probe ran.
    internal let date: Date

    /// Whether a verified token came back.
    internal let succeeded: Bool

    /// The failure's settings reason as shown, nil when the probe
    /// succeeded.
    internal let reason: String?

    /// The failure's settings badge as shown, nil when the probe
    /// succeeded or the verdict predates badges.
    internal let badge: String?
  }

  /// The shipped qualified service, asked until one is configured.
  internal static let defaultAuthority = httpPrefix + defaultAddress

  /// The shipped address shown without the implicit HTTP scheme.
  internal static let defaultAddress = "timestamp.sectigo.com/qualified"

  private static let httpPrefix = "http://"
  private static let schemeSeparator = "://"

  /// The preferences key holding the configured address.
  internal static let key = "timestampAuthority"

  /// The preferences key holding the last Test verdict.
  private static let verificationKey = "timestampAuthorityVerification"

  /// The configured address when one usable is stored, else the default.
  internal static func load(from defaults: UserDefaults) -> String {
    guard
      let configured = Self.configured(in: defaults),
      let resolved = Self.resolvedRequestAddress(configured)
    else {
      return Self.defaultAuthority
    }
    return resolved
  }

  /// The raw configured address, trimmed, or nil.
  ///
  /// Nil when nothing is stored. On macOS without the Time Stamp
  /// pane the key is never read, so a value no pane can show cannot
  /// steer signing.
  internal static func configured(in defaults: UserDefaults) -> String? {
    #if os(macOS) && !FEATURE_TIMESTAMP_CONFIG
      return nil
    #else
      guard let stored = defaults.string(forKey: Self.key) else { return nil }
      let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    #endif
  }

  /// Whether the address names a service this app could ask.
  ///
  /// The same border the signing network enforces, so an address
  /// marked usable here resolves to one a request could carry there. Both
  /// schemes are accepted: timestamping is specified over plain
  /// HTTP and several qualified authorities publish exactly that, so
  /// insisting on one scheme would refuse real services.
  internal static func isUsable(_ address: String) -> Bool {
    resolvedRequestAddress(address) != nil
  }

  /// Records a Test verdict for the probed request address.
  ///
  /// A nil failure is a verified token; anything else records the
  /// failure's reason and badge as shown.
  internal static func recordVerification(
    address: String,
    failure: TimestampClient.Failure?,
    date: Date,
    in defaults: UserDefaults
  ) {
    var record: [String: Any] = [
      "address": address,
      "at": date,
      "ok": failure == nil,
    ]
    record["reason"] = failure?.settingsReason
    record["badge"] = failure?.badgeSymbol
    defaults.set(record, forKey: Self.verificationKey)
  }

  /// The Test verdict for this request address, when the last probe
  /// ran against exactly it.
  ///
  /// A verdict for another address is no verdict: the pane shows
  /// "not tested" instead of vouching for an address it never probed.
  internal static func verification(
    for address: String,
    in defaults: UserDefaults
  ) -> Verification? {
    guard
      let record = defaults.dictionary(forKey: Self.verificationKey),
      let recorded = record["address"] as? String,
      recorded == address,
      let date = record["at"] as? Date,
      let succeeded = record["ok"] as? Bool
    else {
      return nil
    }
    return Verification(
      address: recorded,
      date: date,
      succeeded: succeeded,
      reason: record["reason"] as? String,
      badge: record["badge"] as? String
    )
  }

  /// Stores the address as the service signatures ask.
  ///
  /// An empty address removes the key instead, so the shipped
  /// service - and, on iOS, the Settings default - answers again.
  internal static func store(_ address: String, in defaults: UserDefaults) {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      Self.restoreDefaults(in: defaults)
    } else {
      defaults.set(Self.displayAddress(trimmed), forKey: Self.key)
    }
  }

  /// Forgets the configured address; the shipped service answers again.
  internal static func restoreDefaults(in defaults: UserDefaults) {
    defaults.removeObject(forKey: Self.key)
  }

  /// The editing form of an address: HTTP is implicit; HTTPS stays explicit.
  internal static func displayAddress(_ address: String) -> String {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.lowercased().hasPrefix(httpPrefix) else { return trimmed }
    let unprefixed = String(trimmed.dropFirst(httpPrefix.count))
    return hasExplicitScheme(unprefixed) ? trimmed : unprefixed
  }

  /// Resolves an editing address without changing the transport scheme.
  ///
  /// A bare host and path use HTTP, as the shipped authority does.
  /// Explicit HTTPS stays HTTPS; other explicit schemes remain unusable.
  internal static func resolvedRequestAddress(_ address: String) -> String? {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let resolved = hasExplicitScheme(trimmed) ? trimmed : httpPrefix + trimmed
    guard let url = URL(string: resolved), SigningNetwork.isHttpUrl(url) else { return nil }
    return resolved
  }

  private static func hasExplicitScheme(_ address: String) -> Bool {
    guard let scheme = URLComponents(string: address)?.scheme else { return false }
    return address.hasPrefix(scheme + schemeSeparator)
  }

  /// Removes a blank draft and shows HTTP addresses without their scheme.
  ///
  /// The Settings app writes cleared fields directly, past
  /// `store(_:in:)`; call on iOS launch and activation so the
  /// Settings default shows again.
  internal static func refreshDisplayAddress(in defaults: UserDefaults) {
    guard let stored = defaults.string(forKey: Self.key) else { return }
    if stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      defaults.removeObject(forKey: Self.key)
    } else {
      defaults.set(Self.displayAddress(stored), forKey: Self.key)
    }
  }
}
