// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// The shared cleanup used by identity removal and diagnostic card removal.
@MainActor
internal enum CardIdentityRemoval {
  internal static func perform() async -> CardStateReset.Outcome {
    await perform(
      reset: CardStateReset.perform,
      forgetCredentials: CardCredentialStore.forgetAll,
      clearPhotos: CardPhotoStore.clear,
      removeRemoteConfiguration: removeAllRemoteConfiguration)
  }

  internal static func perform(
    reset: () -> CardStateReset.Outcome,
    forgetCredentials: () -> Void,
    clearPhotos: () -> Void,
    removeRemoteConfiguration: () async -> Bool
  ) async -> CardStateReset.Outcome {
    let identity = reset()
    forgetCredentials()
    clearPhotos()
    let remoteRemoved = await removeRemoteConfiguration()
    return CardStateReset.Outcome(
      lines: identity.lines,
      succeeded: identity.succeeded && remoteRemoved)
  }

  /// Completes pairing and namespace removal before reporting completion.
  private static func removeAllRemoteConfiguration() async -> Bool {
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
        return true
      } catch {
        return false
      }
    }.value
  }
}
