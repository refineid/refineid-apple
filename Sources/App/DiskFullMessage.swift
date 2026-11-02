// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// What the holder is told when the system refused a write for lack of
/// space, in the place the failed operation already reports.
internal enum DiskFullMessage {
  /// The one sentence every operation shows for a full disk.
  internal static var text: String {
    String(localized: "The disk is full. Free some space and try again.")
  }

  /// The full-disk sentence when `error` reports a full disk, otherwise
  /// `otherwise`.
  internal static func message(
    for error: any Error,
    otherwise: @autoclosure () -> String
  ) -> String {
    StorageFailure.isOutOfSpace(error) ? text : otherwise()
  }
}
