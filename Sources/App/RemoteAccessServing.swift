// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import CardCore
  import Foundation

  /// Turns the holder's Remote Access choice into running services.
  ///
  /// Enabling records the choice, asks for the notification
  /// authorization the approval prompts need, and starts discovery and
  /// serving. Disabling stops them again. Pairings stay stored either
  /// way, so turning it back on reconnects without a new code.
  @MainActor
  internal enum RemoteAccessServing {
    internal static func setEnabled(_ enabled: Bool) {
      RemoteAccessGate.setEnabled(enabled)
      if enabled {
        RappAuthorizationInbox.shared.ensureAuthorization()
        RappAutoPairingService.shared.setLocalDiscoveryEnabled(true)
        #if REFINEID_LOCAL_CARD
          if SupportedCardTransports.offersNearField {
            PhonePersistentTokenRelay.shared.resumeAfterUserAction()
          }
        #endif
      } else {
        RappAutoPairingService.shared.setLocalDiscoveryEnabled(false)
        #if REFINEID_LOCAL_CARD
          if SupportedCardTransports.offersNearField {
            PhonePersistentTokenRelay.shared.stopServing()
          }
        #endif
      }
    }
  }
#endif
