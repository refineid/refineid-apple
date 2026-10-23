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
      #if REFINEID_LOCAL_CARD && os(iOS)
        HolderCardServing.availabilityChanged()
        PhonePersistentTokenRelay.shared.start()
        if !SupportedCardTransports.offersNearField {
          PersistentTokenRegistry.shared.start()
        }
      #else
        // Remote use off asks macOS for nothing at launch: no watch
        // starts, and the registry withdraws what an earlier run offered
        // without browsing or dialing (CC-96).
        #if os(macOS)
          RemoteUseSwitch.shared.start()
        #endif
        PersistentTokenRegistry.shared.start()
      #endif
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
}
