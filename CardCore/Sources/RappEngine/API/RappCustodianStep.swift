// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What the custodian does next for its live operation (RAPP v26.10.22
/// §8.2).
///
/// An operation meets them in the order inspect, then the PIN or the read,
/// then the card command.
public enum RappCustodianStep: Equatable, Sendable {
  /// Take the PIN the operation needs: prompt for it, showing the operation,
  /// unless the custodian holds PIN 1 for a browser authentication (§8.2
  /// item 3, §11 item 2); then call `approve` or `deny`.
  case awaitUserApproval
  /// Execute the one approved card command.
  case executeCardCommand
  /// Execute the described read; no private key, no PIN (§8.2 item 6).
  case executeSafeRead
  /// Take the card in the order operations arrived, perform the reads that
  /// precede the PIN, then call `prerequisitesComplete` (§8.2 item 2).
  case inspectPrerequisites
}
