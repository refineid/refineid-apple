// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Distributed notifications about the paired custodian's service.
public enum RappServiceNotificationNames {
  /// Posted when a session closed with `service_withdrawn`: the custodian
  /// stopped serving and the borrowed identity leaves at once.
  public static let serviceWithdrawnDarwinNotification = "fi.refineid.service.withdrawn"

  /// Posted when the custodian closed a session with `pairing_revoked`:
  /// the pairing is gone and the borrowed identity leaves at once (RAPP
  /// v26.10.21 §4.6 item 4).
  public static let pairingRevokedDarwinNotification = "fi.refineid.service.pairing-revoked"
}
