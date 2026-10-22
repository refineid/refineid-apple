// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// The time-stamp authorities, in the order they are asked.
///
/// These are the services an archival signature asks for its
/// timestamp, first answer wins. One is shipped; each one more costs
/// every later reader a chain to walk, and whoever configures one
/// answers for it. URLs are configuration, not secrets: they name
/// public services and live in preferences.
internal enum TimestampAuthorityStore {
  /// The preferences key holding the ordered list.
  private static let key = "timestampAuthorities"

  /// The shipped set: one qualified service.
  ///
  /// One rather than four. The list is asked in order and the first
  /// to answer wins, so the others are never reached on a working
  /// network - but every authority that does answer brings its own
  /// certificate chain, and an archival signature carries the chain
  /// and the revocation data proving it for each. A document signed
  /// twice through four authorities can end up with four chains to
  /// walk, which is work for every reader that opens it ever after.
  internal static let defaults: [String] = [
    "http://timestamp.sectigo.com/qualified"
  ]

  /// The preferences key of the per-authority usernames.
  private static let usersKey = "timestampAuthorityUsers"

  /// The keychain service holding per-authority passwords.
  private static let passwordService = "fi.refineid.tsa-basic-auth"

  /// The configured list, or the defaults when nothing was changed.
  internal static func load() -> [String] {
    #if FEATURE_TIMESTAMP_CONFIG
      UserDefaults.standard.stringArray(forKey: Self.key) ?? Self.defaults
    #else
      Self.defaults
    #endif
  }

  /// The Basic-auth credentials for one authority, or nil when it
  /// is a public service needing none.
  internal static func credentials(
    for authority: String
  ) -> (username: String, password: String)? {
    guard let user = Self.username(for: authority) else { return nil }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.passwordService,
      kSecAttrAccount as String: authority,
      kSecReturnData as String: true,
    ]
    var item: CFTypeRef?
    guard
      SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data,
      let password = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    return (user, password)
  }

  /// The Basic-auth username for one authority; nil means the
  /// authority is public and no authentication is sent.
  internal static func username(for authority: String) -> String? {
    let users = UserDefaults.standard.dictionary(forKey: Self.usersKey)
    return users?[authority] as? String
  }
}
