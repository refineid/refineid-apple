// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Shared notification and identifier constants for RAPP card prompt notifications.
public enum RappCardPromptNotificationNames {
  /// Darwin distributed notification posted when an active RAPP operation needs the card presented.
  public static let cardNeededDarwinNotification = "fi.refineid.card.needed"

  /// Darwin distributed notification posted when card wait ends or the prompt is dismissed.
  public static let cardDismissDarwinNotification = "fi.refineid.card.dismiss"

  /// UserNotification request identifier for transient macOS card prompt banners.
  public static let userNotificationRequestIdentifier = "fi.refineid.card.prompt.banner"
}
