// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD
  import CardCore
  import Foundation

  /// Clears the vault's namespace from the login keychain, once.
  ///
  /// The vault lives in the shared data-protection group. An item of its
  /// namespace in the login keychain, a pairing's private key included, is
  /// nothing the app can use and the holder would otherwise have no way to
  /// see gone (AGENTS.md Rule #4). A pairing kept there is not carried over:
  /// the holder pairs again.
  ///
  /// The sweep counts as done only when every item went. A failure leaves it
  /// due at the next launch, and forgetting everything clears the same items
  /// in any case (``RappDeviceVault/deleteServiceNamespace(_:)``).
  internal enum RappVaultFileKeychainSweep {
    /// The defaults key recording that the sweep finished.
    internal static let doneKey = "fi.refineid.vault.file-keychain-swept"

    /// Sweeps unless an earlier launch finished it.
    internal static func run(defaults: UserDefaults, sweep: () throws -> Void) {
      guard !defaults.bool(forKey: doneKey) else { return }
      do {
        try sweep()
        defaults.set(true, forKey: doneKey)
      } catch {
        #if DEBUG
          DevErrorLog.report(
            "file keychain sweep failed: \(DevErrorLog.reason(error))", source: .app)
        #endif
      }
    }
  }
#endif
