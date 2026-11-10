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
  /// The shipped qualified service, asked until one is configured.
  internal static let defaultAuthority = "http://timestamp.sectigo.com/qualified"

  /// The preferences key holding the configured address.
  internal static let key = "timestampAuthority"

  /// The configured address when one usable is stored, else the default.
  internal static func load(from defaults: UserDefaults) -> String {
    guard
      let configured = defaults.string(forKey: Self.key),
      Self.isUsable(configured)
    else {
      return Self.defaultAuthority
    }
    return configured
  }

  /// Whether the address names a service this app could ask.
  ///
  /// Both schemes are accepted: timestamping is specified over plain
  /// HTTP and several qualified authorities publish exactly that, so
  /// insisting on one scheme would refuse real services.
  internal static func isUsable(_ address: String) -> Bool {
    guard
      let url = URL(string: address),
      let scheme = url.scheme?.lowercased(),
      url.host != nil
    else {
      return false
    }
    return scheme == "http" || scheme == "https"
  }

  /// Stores the address as the service signatures ask.
  internal static func store(_ address: String, in defaults: UserDefaults) {
    defaults.set(address, forKey: Self.key)
  }

  /// Forgets the configured address; the shipped service answers again.
  internal static func restoreDefaults(in defaults: UserDefaults) {
    defaults.removeObject(forKey: Self.key)
  }
}
