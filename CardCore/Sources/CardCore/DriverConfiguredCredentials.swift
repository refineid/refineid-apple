// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoTokenKit
import Foundation
import ObjCExceptionGuard

/// The app's view of CryptoTokenKit's configuration store for its own
/// token driver.
///
/// The store no longer carries the card access number.
/// `driverConfigurations` is populated for the hosting application
/// only - every other caller, the token driver itself included, is
/// handed an empty store - so a number written here was unreadable
/// exactly where it was needed. `CardCanOffer` carries it now, in the
/// shared keychain group both processes can read.
///
/// What remains here is the store as the system lists it: the named
/// entry earlier versions published, withdrawn so it does not outlive
/// them, and the identity configurations the debug reset drops.
public enum DriverConfiguredCredentials {
  /// Serializes the configuration reads below.
  private static let lock = NSLock()

  /// The driver whose configuration this is: `com.apple.ctk.class-id`
  /// in the token extension's Info.plist.
  private static let classID = CardTokenNamespace.driverClassIdentifier

  /// Names the one entry this app keeps.
  ///
  /// A fixed name rather than a card's identifier, because the card
  /// access number this Mac holds is a single stored value -- the same
  /// one the keychain keeps under a single account -- and because a card
  /// answers with a different identifier on each of its two interfaces,
  /// so keying by card would need the number stored once per interface
  /// to be found from either.
  ///
  /// Public because of what it costs: every token configuration is keyed
  /// by an instance identifier, and
  /// the system lists those identifiers as tokens whether or not a token
  /// was ever created for one. This entry therefore appears alongside
  /// real cards in `TKTokenWatcher`, holding no keychain items and so
  /// offering nothing to Safari -- but anything asking "is a card
  /// available?" has to exclude it by name, or it answers yes with no
  /// card present.
  public static let configurationInstanceID = "card-access-number"

  /// The configuration store, or nil in a process that is not the
  /// driver's hosting application.
  ///
  /// Read through the exception guard: the store is an XPC call into
  /// `ctkd`, and a daemon mid-restart can answer it with an
  /// Objective-C exception instead of a value. Caught, that answer
  /// becomes what it means here - no store readable right now.
  ///
  /// Serialized: opening the configuration connection from two threads
  /// at once traps inside `xpc_connection_resume`, and that trap is a
  /// process signal no exception guard can catch.
  private static var configuration: TKTokenDriver.Configuration? {
    lock.withLock {
      var stores: [String: TKTokenDriver.Configuration] = [:]
      let raised = CardCoreCatchException {
        stores = TKTokenDriver.Configuration.driverConfigurations
      }
      guard raised == nil else { return nil }
      return stores[Self.classID]
    }
  }

  /// Drops only card-identity configurations, preserving stored setup.
  ///
  /// The driver class is RefineID's private namespace, so every entry
  /// except the two named setup channels is an identity published by
  /// this app or an earlier version of it. This deliberately catches
  /// legacy ATR-hash instance names as well as current
  /// `refineid-card-*` names without touching another driver's tokens.
  public static func dropIdentityTokenConfigurations() -> Int {
    guard let configuration else { return 0 }
    let identities = Self.identityTokenConfigurationIDs(in: configuration)
    for instance in identities {
      configuration.removeTokenConfiguration(for: instance)
    }
    return identities.count
  }

  /// How many card identities this driver configuration still holds.
  ///
  /// Presence only. The setup screen uses this to offer its destructive
  /// forget action for a stale partial identity without reading a token,
  /// touching a card, or exposing configuration data.
  public static func identityTokenConfigurationCount() -> Int {
    guard let configuration else { return 0 }
    return Self.identityTokenConfigurationIDs(in: configuration).count
  }

  /// Identity instance names, excluding the setup-only channel.
  private static func identityTokenConfigurationIDs(
    in configuration: TKTokenDriver.Configuration
  ) -> [String] {
    configuration.tokenConfigurations.keys.filter { instance in
      instance != Self.configurationInstanceID
    }
  }

  /// The remote-card instance names among the given ones.
  ///
  /// The remote card publishes under `PersistentTokenIdentity.classID`;
  /// under this driver's class, an instance carrying its name is the
  /// configuration a build before the driver split wrote, which the
  /// system lists as a present card for as long as it stays.
  public static func displacedRemoteCardConfigurationIDs(
    among instanceIDs: some Sequence<String>
  ) -> [String] {
    instanceIDs.filter { instance in
      instance.hasPrefix(PersistentTokenIdentity.instancePrefix)
    }
  }

  /// Drops the remote-card identities left under this driver's class,
  /// and answers how many went.
  ///
  /// Narrower than `dropIdentityTokenConfigurations`: card identities,
  /// live ones included, stay untouched, so this is safe to run with a
  /// card working in the reader.
  public static func dropDisplacedRemoteCardConfigurations() -> Int {
    guard let configuration else { return 0 }
    let displaced = Self.displacedRemoteCardConfigurationIDs(
      among: configuration.tokenConfigurations.keys)
    for instance in displaced {
      configuration.removeTokenConfiguration(for: instance)
    }
    return displaced.count
  }

  /// Withdraws it, so forgetting the card forgets it here too.
  internal static func withdraw() {
    configuration?.removeTokenConfiguration(for: Self.configurationInstanceID)
  }
}
