// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

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
