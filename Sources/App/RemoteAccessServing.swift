// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)
  import CardCore
  import Foundation

  /// Turns the holder's Remote Access choice into running services.
  ///
  /// Enabling records the choice and starts discovery and serving; the
  /// notification authorization the approval prompts need is asked
  /// separately, after its own explanation. Disabling stops the
  /// services; the caller wipes the pairings too, so off leaves no
  /// remote state behind.
  @MainActor
  internal enum RemoteAccessServing {
    internal static func setEnabled(_ enabled: Bool) {
      RemoteAccessGate.setEnabled(enabled)
      if enabled {
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
