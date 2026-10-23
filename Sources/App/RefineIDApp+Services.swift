// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine

#if os(macOS)
  import AppKit
#endif

extension RefineIDApp {
  private static var pairingsChangeObserver: (any NSObjectProtocol)?

  #if os(macOS)
    internal static func configurePlatformDefaults() {
      SingleInstance.enforce()
      UserDefaults.standard.set(
        true, forKey: "NSDisabledCharacterPaletteMenuItem"
      )
      UserDefaults.standard.set(
        true, forKey: "NSDisabledDictationMenuItem"
      )
      UserDefaults.standard.set(
        false, forKey: "NSFullScreenMenuItemEverywhere"
      )
      MainMenuPruner.start()
    }
  #endif

  internal static func startRemoteServices() {
    // Every message a peer sent that the protocol refuses shows among the
    // development errors, named by its type and the rule it broke.
    #if DEBUG
      RappRefusalLog.install { line in
        DevErrorLog.report("message refused: \(line)", source: .app)
      }
    #endif
    #if REFINEID_REMOTE_CARD
      guard !TestCredentialEnvironment.isTestMode else { return }
      #if DEBUG
        if DebugLaunchModes.selected() != nil { return }
      #endif

      let vault = RappDeviceVault()
      if vault.dropUnreadablePairs() > 0 {
        PersistentTokenRegistry.withdrawPublishedIdentity()
      }
      startFromThePairings()
      #if os(macOS)
        RappCardPromptNotificationRelay.shared.start()
        #if REFINEID_STREAM_TRANSPORT
          HeldSessionHandoffPort.start()
        #endif
      #endif
      RappAutoPairingService.shared.start()

      pairingsChangeObserver = NotificationCenter.default.addObserver(
        forName: RappAutoPairingService.pairingsDidChangeNotification,
        object: nil,
        queue: .main
      ) { _ in
        MainActor.assumeIsolated {
          #if os(macOS)
            PersistentTokenRegistry.shared.startAfterPairing()
          #elseif os(iOS) && REFINEID_LOCAL_CARD
            PhonePersistentTokenRelay.shared.start()
            if !SupportedCardTransports.offersNearField {
              PersistentTokenRegistry.shared.startAfterPairing()
            }
          #endif
        }
      }
    #endif
  }

  #if REFINEID_REMOTE_CARD
    /// Sweeps the pairings for idle expiry (RAPP v26.10.22 §4.6 item 5),
    /// then serves or follows from what remains, and sweeps again while the
    /// app runs.
    ///
    /// On the Mac, remote use is restored on only while a pairing remains;
    /// off, it asks macOS for nothing, and the registry withdraws what an
    /// earlier run offered without browsing or dialing (CC-96, CC-101).
    private static func startFromThePairings() {
      #if os(macOS)
        RemoteUseSwitch.shared.start(
          pairingRemains: PersistentTokenRegistry.sweepIdlePairingsAtLaunch())
      #else
        PersistentTokenRegistry.sweepIdlePairingsAtLaunch()
      #endif
      #if REFINEID_LOCAL_CARD && os(iOS)
        HolderCardServing.availabilityChanged()
        PhonePersistentTokenRelay.shared.start()
        PhonePersistentTokenRelay.shared.idleSweep.start {
          PhonePersistentTokenRelay.shared.sweepIdlePairings()
        }
        guard !SupportedCardTransports.offersNearField else { return }
      #endif
      PersistentTokenRegistry.shared.start()
      PersistentTokenRegistry.shared.idleSweep.start {
        PersistentTokenRegistry.shared.sweepIdlePairings()
      }
    }
  #endif
}
