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
    #if REFINEID_REMOTE_CARD
      await perform(
        reset: CardStateReset.perform,
        forgetCredentials: CardCredentialStore.forgetCardAccessNumber,
        removeRemoteConfiguration: removeAllRemoteConfiguration)
    #else
      // With the remote card compiled out no pairing can exist to remove.
      await perform(
        reset: CardStateReset.perform,
        forgetCredentials: CardCredentialStore.forgetCardAccessNumber,
        removeRemoteConfiguration: { ConfigurationRemoval(succeeded: true, failures: []) })
    #endif
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
  #if REFINEID_REMOTE_CARD
    private static func removeAllRemoteConfiguration() async -> ConfigurationRemoval {
      defer {
        NotificationCenter.default.post(
          name: RappPairingModel.pairingsDidChangeNotification, object: nil)
      }
      let vault = RappDeviceVault()
      let catalog = RappPairCatalog(vault: vault)
      let pairs = (try? await catalog.activePairs()) ?? []
      await endRemoteSessionsAndForgetPairs(pairs: pairs, catalog: catalog)
      try? vault.clearSelectedPair()
      return await deleteNamespaceExcludingNotices()
    }

    private static func endRemoteSessionsAndForgetPairs(
      pairs: [RappPairingCoordinator.PairSummary],
      catalog: RappPairCatalog
    ) async {
      #if os(macOS)
        let closing = PersistentTokenRegistry.shared.holderSession?.pairID
        let closes = PersistentTokenRegistry.shared.revokeHolderSession()
        let told = await closes?.value ?? false
        if told, let closing {
          _ = try? await catalog.revoke(pairID: closing)
        }
        for pair in pairs where !told || pair.pairID != closing {
          _ = try? await catalog.forget(pairID: pair.pairID)
        }
        PersistentTokenRegistry.withdrawPublishedIdentity()
      #elseif os(iOS)
        #if REFINEID_LOCAL_CARD
          for pair in pairs {
            let told = await PhonePersistentTokenRelay.shared.closeForRevocation(
              pairID: pair.pairID)
            if told {
              _ = try? await catalog.revoke(pairID: pair.pairID)
            } else {
              _ = try? await catalog.forget(pairID: pair.pairID)
            }
          }
        #else
          for pair in pairs {
            _ = try? await catalog.forget(pairID: pair.pairID)
          }
        #endif
        RemoteAccessServing.setEnabled(false)
      #endif
    }

    private static func deleteNamespaceExcludingNotices() async -> ConfigurationRemoval {
      await Task.detached(priority: .userInitiated) {
        do {
          _ = try RappDeviceVault().deleteServiceNamespace(excludingRevocationNotices: true)
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
  #endif
}
