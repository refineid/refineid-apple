// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// The notices a requester posts inside its own process while an
  /// operation runs, so the app can show the card prompt the custodian is
  /// waiting on and follow the pairing's end.
  ///
  /// The notices travel on the process's own notification center and never
  /// leave it: only this process's requester sessions post them, and only
  /// this process's app hears them.
  public enum RappRequesterNotices {
    /// An operation waits for the holder to present the card.
    public static let cardNeeded = Notification.Name("fi.refineid.card.needed")

    /// The card was found, or the operation ended without it.
    public static let cardWaitEnded = Notification.Name("fi.refineid.card.dismiss")

    /// A session closed with `service_withdrawn`: the custodian stopped
    /// serving and the borrowed identity leaves at once.
    public static let serviceWithdrawn = Notification.Name("fi.refineid.service.withdrawn")

    /// The custodian closed a session with `pairing_revoked`: the pairing
    /// is gone and the borrowed identity leaves at once (RAPP v26.10.29
    /// §4.6 item 4).
    public static let pairingRevoked = Notification.Name("fi.refineid.service.pairing-revoked")

    /// Posts the notice `progress` calls for, if any.
    internal static func post(progress: ProgressEvent) {
      switch progress {
      case .waitingForCard:
        post(cardNeeded)

      case .cardWaitEnded:
        post(cardWaitEnded)

      default:
        break
      }
    }

    internal static func post(_ name: Notification.Name) {
      NotificationCenter.default.post(name: name, object: nil)
    }
  }
#endif
