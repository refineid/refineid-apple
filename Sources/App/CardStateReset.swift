// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Foundation
import Security

/// Milliseconds in one second, for the stamp a revocation carries.
private let millisecondsPerSecond: TimeInterval = 1_000

/// Removes only the Safari identity state published by this app.
///
/// The holder's CAN and optional PIN1 remain stored. Reset is recovery
/// for a stale CryptoTokenKit registration, not a request to erase card
/// setup and force secret re-entry.
internal enum CardStateReset {
  /// One completed reset, including enough detail for diagnostics.
  internal struct Outcome {
    internal let lines: [String]
    internal let succeeded: Bool

    internal var summary: String {
      succeeded
        ? String(localized: "RefineID's Safari card identities were reset.")
        : String(localized: "Some RefineID Safari identity state could not be removed.")
    }
  }

  /// Whether this device has any card or identity state to forget.
  ///
  /// Every lookup is passive. In particular, this does not enumerate
  /// token keychain items or wake the built-in NFC slot merely to decide
  /// whether a destructive button should be visible.
  internal static func hasForgettableState() -> Bool {
    let credentials = CardCredentialStore.contents()
    return credentials.hasCardAccessNumber
      || credentials.hasPin1
      || PrimeStore.storedCount() > 0
      || DriverConfiguredCredentials.identityTokenConfigurationCount() > 0
      || !Self.registeredOurTokenIDs().isEmpty
  }

  /// Clears registrations, identity configurations, primes, and trace.
  internal static func perform() -> Outcome {
    var lines = ["=== reset RefineID Safari identities ==="]
    let registration = Self.unregisterOurTokens()
    lines += registration.lines

    let dropped = DriverConfiguredCredentials.dropIdentityTokenConfigurations()
    lines.append("RefineID identity configurations removed: \(dropped)")

    PrimeStore.forgetAll()
    lines.append("RefineID prime store: cleared")
    #if os(iOS) && REFINEID_LOCAL_CARD
      Task { @MainActor in HolderCardServing.availabilityChanged() }
    #endif

    let revoked = Self.revokeEveryPairing()
    lines.append("RefineID pairings revoked: \(revoked)")

    #if os(macOS) || os(iOS)
      Task { @MainActor in
        PersistentTokenRegistry.withdrawPublishedIdentity()
        #if REFINEID_STREAM_TRANSPORT
          PersistentTokenRegistry.shared.stopWatchingPresence()
        #endif
      }
    #endif

    let traceStatus = ExtensionTrace.clear()
    let traceCleared = traceStatus == errSecSuccess || traceStatus == errSecItemNotFound
    lines.append(
      traceCleared
        ? "RefineID extension trace: cleared"
        : "RefineID extension trace: clear failed (\(traceStatus))")
    lines.append("Stored CAN and PIN 1: preserved")
    lines.append("=== end ===")
    return Outcome(
      lines: lines,
      succeeded: registration.succeeded && traceCleared)
  }

  /// Revokes every pairing this device holds, and returns how many.
  ///
  /// A pairing is state this device keeps about another, so a reset that
  /// claims a known zero has to take them too. Leaving them behind was how
  /// a device came to hold nine records for one peer, of which one answered.
  private static func revokeEveryPairing() -> Int {
    let vault = RappDeviceVault()
    let pairIDs = (try? vault.activePairIDs()) ?? []
    let now = UInt64(Date().timeIntervalSince1970 * millisecondsPerSecond)
    var revoked = 0
    for pairID in pairIDs {
      guard (try? vault.revokePair(pairID: pairID, revokedAtMilliseconds: now)) != nil
      else { continue }
      RappPairNames.forget(pairID: pairID)
      revoked += 1
    }
    try? vault.clearSelectedPair()
    return revoked
  }

  /// Unregisters only token IDs issued by this app's CTK class.
  private static func unregisterOurTokens() -> (
    lines: [String],
    succeeded: Bool
  ) {
    #if os(iOS)
      let manager = TKSmartCardTokenRegistrationManager.default
      let ours = Self.registeredOurTokenIDs()
      guard !ours.isEmpty else {
        return (["RefineID Safari registrations: none"], true)
      }
      var succeeded = true
      let lines = ours.map { tokenID in
        do {
          try manager.unregisterSmartCard(tokenID: tokenID)
          return "Unregistered \(tokenID)"
        } catch {
          succeeded = false
          return "Could not unregister \(tokenID): \(error)"
        }
      }
      return (lines, succeeded)
    #else
      return (["RefineID Safari registrations: not used on this platform"], true)
    #endif
  }

  /// RefineID registrations already known to CryptoTokenKit.
  private static func registeredOurTokenIDs() -> [String] {
    #if os(iOS)
      return TKSmartCardTokenRegistrationManager.default.registeredSmartCardTokens
        .filter(CardTokenNamespace.owns(tokenIdentifier:))
        .sorted()
    #else
      return []
    #endif
  }
}
