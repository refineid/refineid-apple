// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import os.log

/// Withdraws remote-card identities configured under the card driver's
/// class.
///
/// The remote card publishes under its own driver class; an instance
/// carrying its name under the card driver's class is one a build
/// before the driver split configured there. The system lists such an
/// entry as a present card for as long as it stays, so a Mac with no
/// reader attached offered a ready identity read from it.
///
/// Reading the configuration store is a synchronous call into `ctkd`,
/// so this never runs from the app initializer, which must not wait on
/// another process: the first screen's task calls it, and it leaves the
/// main actor before touching the store.
internal enum DisplacedRemoteCardWithdrawal {
  #if DEBUG
    /// Withdrawal counts, in development builds only.
    ///
    /// Never an identifier. A production build writes no diagnostics.
    private static let log = Logger(
      subsystem: "fi.refineid.ReFineID", category: "displaced-remote-card"
    )
  #endif

  /// Whether this run already withdrew.
  @MainActor private static var performed = false

  /// Withdraws once per run, off the main actor.
  @MainActor
  internal static func performOnce() {
    guard !performed else { return }
    performed = true
    Task.detached(priority: .utility) {
      let dropped = DriverConfiguredCredentials.dropDisplacedRemoteCardConfigurations()
      let droppedIdentities = DriverConfiguredCredentials.dropIdentityTokenConfigurations()
      #if DEBUG
        Self.log.info(
          "withdrew \(dropped) displaced remote-card and \(droppedIdentities) identity configuration(s)"
        )
      #else
        _ = dropped
        _ = droppedIdentities
      #endif
    }
  }
}
