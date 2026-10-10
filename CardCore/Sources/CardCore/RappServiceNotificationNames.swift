// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Distributed notifications about the paired custodian's service.
public enum RappServiceNotificationNames {
  /// Posted when a session closed with `service_withdrawn`: the custodian
  /// stopped serving and the borrowed identity leaves at once.
  public static let serviceWithdrawnDarwinNotification = "fi.refineid.service.withdrawn"
}
