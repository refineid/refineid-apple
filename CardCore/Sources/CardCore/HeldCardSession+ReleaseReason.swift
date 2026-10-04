// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

extension HeldCardSession {
  /// The lifecycle event that invalidates a retained field.
  public enum ReleaseReason: String, Sendable {
    case explicit = "explicit"
    case slotMissing = "slotMissing"
    case cardRemoved = "cardRemoved"
    case activityTimeout = "activityTimeout"
    case preparationFailed = "preparationFailed"
    case signingFailed = "signingFailed"
    case tokenDestroyed = "tokenDestroyed"
    case revoked = "revoked"
  }
}
