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
    guard !TestCredentialEnvironment.isTestMode else { return }
    #if DEBUG
      if DebugLaunchModes.selected() != nil { return }
    #endif

    #if REFINEID_LOCAL_CARD && os(iOS)
      HolderCardServing.availabilityChanged()
      PhonePersistentTokenRelay.shared.start()
      if !SupportedCardTransports.offersNearField {
        PersistentTokenRegistry.shared.start()
      }
    #else
      PersistentTokenRegistry.shared.start()
    #endif
    RappAutoPairingService.shared.start()

    pairingsChangeObserver = NotificationCenter.default.addObserver(
      forName: Notification.Name("fi.refineid.pairingsDidChange"),
      object: nil,
      queue: .main
    ) { _ in
      MainActor.assumeIsolated {
        #if os(macOS)
          PersistentTokenRegistry.shared.startAfterPairing()
        #elseif os(iOS) && REFINEID_LOCAL_CARD
          if let ids = try? RappDeviceVault().activePairIDs(), !ids.isEmpty {
            PhonePersistentTokenRelay.shared.resumeAfterUserAction()
          }
          if !SupportedCardTransports.offersNearField {
            PersistentTokenRegistry.shared.startAfterPairing()
          }
        #endif
      }
    }
  }
}
