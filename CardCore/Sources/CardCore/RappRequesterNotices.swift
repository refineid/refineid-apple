// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// The notices a requester posts inside its own process while an
  /// operation runs, so the app can show what the custodian is waiting on
  /// (the holder's unlock or the card) and follow the pairing's end.
  ///
  /// The notices travel on the process's own notification center and never
  /// leave it. A system-wide center takes a post of any name from any local
  /// process, so nothing that center delivers could carry authority here.
  public enum RappRequesterNotices {
    /// An operation waits for the holder to present the card.
    public static let cardNeeded = Notification.Name("fi.refineid.card.needed")

    /// The operation waits for the holder to unlock the phone
    /// (`waiting_for_unlock`, RAPP v26.11.2 §8.2 item 3).
    public static let unlockNeeded = Notification.Name("fi.refineid.phone.unlock")

    /// The card was found, the phone proceeded, or the operation ended.
    public static let cardWaitEnded = Notification.Name("fi.refineid.card.dismiss")

    /// A session closed with `service_withdrawn`: the custodian stopped
    /// serving and the borrowed identity leaves at once.
    public static let serviceWithdrawn = Notification.Name("fi.refineid.service.withdrawn")

    /// The custodian closed a session with `pairing_revoked`; the session
    /// has already removed the pairing from the vault (RAPP v26.11.2 §4.6
    /// item 4).
    public static let pairingRevoked = Notification.Name("fi.refineid.service.pairing-revoked")

    /// Posts the notice `progress` calls for, if any.
    ///
    /// The unlock prompt ends with the custodian's next word: the PIN
    /// prompt on its screen, the card wait, or the operation's end.
    internal static func post(progress: ProgressEvent) {
      switch progress {
      case .waitingForUnlock:
        post(unlockNeeded)

      case .consentShown:
        post(cardWaitEnded)

      case .waitingForCard:
        post(cardNeeded)

      case .cardWaitEnded:
        post(cardWaitEnded)

      case .queued:
        break
      }
    }

    internal static func post(_ name: Notification.Name) {
      NotificationCenter.default.post(name: name, object: nil)
    }
  }
#endif
