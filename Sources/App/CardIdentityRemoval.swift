// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// The shared cleanup used by identity removal and diagnostic card removal.
@MainActor
internal enum CardIdentityRemoval {
  internal struct ConfigurationRemoval: Sendable {
    internal let succeeded: Bool
    internal let failures: [String]
  }

  internal static func perform() async -> CardStateReset.Outcome {
    await perform(
      reset: CardStateReset.perform,
      forgetCredentials: CardCredentialStore.forgetCardAccessNumber,
      removeRemoteConfiguration: removeAllRemoteConfiguration)
  }

  internal static func perform(
    reset: () -> CardStateReset.Outcome,
    forgetCredentials: () -> Void,
    removeRemoteConfiguration: () async -> ConfigurationRemoval
  ) async -> CardStateReset.Outcome {
    let identity = reset()
    forgetCredentials()
    let remoteRemoved = await removeRemoteConfiguration()
    return CardStateReset.Outcome(
      lines: identity.lines + remoteRemoved.failures,
      succeeded: identity.succeeded && remoteRemoved.succeeded)
  }

  /// Completes pairing and namespace removal before reporting completion.
  ///
  /// With every pairing gone the phone has nothing to serve, so Remote
  /// Access turns off as well; turning it back on starts a new pairing.
  private static func removeAllRemoteConfiguration() async -> ConfigurationRemoval {
    #if os(iOS)
      RemoteAccessServing.setEnabled(false)
    #endif
    defer {
      NotificationCenter.default.post(
        name: RappPairingModel.pairingsDidChangeNotification, object: nil)
    }
    let vault = RappDeviceVault()
    let catalog = RappPairCatalog(vault: vault)
    if let pairs = try? await catalog.activePairs() {
      for pair in pairs {
        try? await catalog.revoke(pairID: pair.pairID)
      }
    }
    try? vault.clearSelectedPair()
    RappPairNames.forgetAll()
    return await Task.detached(priority: .userInitiated) {
      do {
        _ = try RappDeviceVault().deleteServiceNamespace()
        return ConfigurationRemoval(succeeded: true, failures: [])
      } catch RappDeviceVault.Failure.unavailable(let status) {
        return ConfigurationRemoval(
          succeeded: false,
          failures: ["Cleanup failure: keychain namespace (OSStatus=\(status))"])
      } catch {
        return ConfigurationRemoval(
          succeeded: false,
          failures: ["Cleanup failure: keychain namespace (unexpected storage error)"])
      }
    }.value
  }
}
