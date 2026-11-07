// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// The process-wide notices a requester posts while an operation runs,
  /// so the app can show what the custodian is waiting on: the holder's
  /// unlock or the card.
  ///
  /// Only macOS carries the prompt in another process; elsewhere nothing
  /// is posted.
  internal enum RappRequesterNotices {
    /// Posts the notice `progress` calls for, if any.
    ///
    /// The unlock prompt ends with the custodian's next word: the PIN
    /// prompt on its screen, the card wait, or the operation's end.
    internal static func post(progress: ProgressEvent) {
      switch progress {
      case .waitingForUnlock:
        post(RappCardPromptNotificationNames.unlockNeededDarwinNotification)

      case .consentShown:
        post(RappCardPromptNotificationNames.cardDismissDarwinNotification)

      case .waitingForCard:
        post(RappCardPromptNotificationNames.cardNeededDarwinNotification)

      case .cardWaitEnded:
        post(RappCardPromptNotificationNames.cardDismissDarwinNotification)

      case .queued:
        break
      }
    }

    internal static func post(_ name: String) {
      #if os(macOS)
        DistributedNotificationCenter.default().postNotificationName(
          Notification.Name(name),
          object: nil,
          userInfo: nil,
          deliverImmediately: true
        )
      #endif
    }
  }
#endif
