// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Shared notification and identifier constants for RAPP card prompt notifications.
public enum RappCardPromptNotificationNames {
  /// Darwin distributed notification posted when an active RAPP operation needs the card presented.
  public static let cardNeededDarwinNotification = "fi.refineid.card.needed"

  /// Darwin distributed notification posted when card wait ends or the prompt is dismissed.
  public static let cardDismissDarwinNotification = "fi.refineid.card.dismiss"

  /// Darwin distributed notification posted when the operation waits for the
  /// holder to unlock the phone (`waiting_for_unlock`, RAPP v26.11.2 §8.2
  /// item 3).
  public static let unlockNeededDarwinNotification = "fi.refineid.phone.unlock"

  /// UserNotification request identifier for transient macOS card prompt banners.
  public static let userNotificationRequestIdentifier = "fi.refineid.card.prompt.banner"
}
