// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)
  import CardCore
  import Foundation
  import RappEngine

  /// Dialling the phone again after a loss of the session, within the
  /// redial window (RAPP v26.11.8 §8.3).
  extension PersistentTokenRegistry {
    /// How long the phone is redialled over the stream after a loss of the session, or after the
    /// first failed dial since it last appeared, before dialling waits for its next appearance
    /// (RAPP v26.11.8 §8.3, `redial_window_ms`).
    ///
    /// Bluetooth dials on, each waiting for the phone's advertisement (CC-50). The offered identity
    /// follows ``RemoteIdentityOffer`` alone.
    internal static let redialWindow = Duration.milliseconds(Int64(rappRedialWindowMs()))

    /// Dials again once the slot's back-off is over; over the stream only
    /// within the redial window, ``redialWindow`` from the loss or the
    /// first failed dial since the phone last appeared (RAPP v26.11.8
    /// §8.3).
    internal func scheduleRedial() {
      redialTask?.cancel()
      let now = ContinuousClock.now
      let since = continuousFailureSince ?? now
      continuousFailureSince = since
      let overBluetooth = transportPolicy.nextDial == .bluetooth
      guard overBluetooth || now - since < Self.redialWindow else {
        // The loop has not produced a usable session within the deadline.
        // Stop dialing and leave a terminal state instead of looping; a
        // fresh advertisement (holderIsAdvertising) or a user action
        // starts a new attempt. The offer's grace has run by now.
        #if DEBUG
          DevErrorLog.report(
            "phone session: no session within the redial window, stopped dialling",
            source: .app)
        #endif
        continuousFailureSince = nil
        redialTask = nil
        return
      }
      let dialAt = sessionSlot.nextDialAt ?? now
      redialTask = Task { @MainActor in
        try? await Task.sleep(until: dialAt, clock: .continuous)
        guard !Task.isCancelled else { return }
        redialTask = nil
        openHolderSession()
      }
    }
  }
#endif
