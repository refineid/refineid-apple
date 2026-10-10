// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import OSLog

/// The step a signature in flight is on.
internal enum DocumentSigningPhase: Equatable, Sendable {
  /// The card in this Mac's reader is signing.
  case card

  /// The paired phone holds the request until the holder answers it there.
  case phone

  /// An authority is timestamping the signature.
  case timestamp

  /// Certificate status is being collected for the archival signature.
  case validation

  /// One short line naming the step.
  internal var note: String {
    switch self {
    case .card:
      String(localized: "Signing document…")

    case .phone:
      String(localized: "Continue on your phone")

    case .timestamp:
      String(localized: "Timestamping…")

    case .validation:
      String(localized: "Fetching validity information…")
    }
  }
}

extension DocumentSigner {
  /// Where the signature in flight reports its steps.
  @TaskLocal internal static var phaseObserver: (@Sendable (DocumentSigningPhase) -> Void)?

  #if DEBUG
    private static let phaseLogger = Logger(
      subsystem: "fi.refineid.ReFineID", category: "signing-phase"
    )
  #endif

  /// Tells the observer, if any, which step has begun.
  internal static func report(_ phase: DocumentSigningPhase) {
    #if DEBUG
      phaseLogger.notice("[DocumentSigner] phase \(String(describing: phase), privacy: .public)")
    #endif
    Self.phaseObserver?(phase)
  }

  #if DEBUG
    /// Marks a point between steps in the debug log.
    internal static func phaseTrace(_ point: String) {
      phaseLogger.notice("[DocumentSigner] \(point, privacy: .public)")
    }
  #endif
}
