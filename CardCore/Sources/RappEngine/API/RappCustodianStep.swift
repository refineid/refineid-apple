// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What the custodian does next for its live operation (RAPP v26.10.21
/// §8.2).
///
/// An operation meets them in the order inspect, then consent or the read,
/// then the card command.
public enum RappCustodianStep: Equatable, Sendable {
  /// Present the operation and wait for the holder (§8.2 item 3).
  case awaitUserApproval
  /// Execute the one approved card command.
  case executeCardCommand
  /// Execute the described read; no private key, no PIN (§8.2 item 6).
  case executeSafeRead
  /// Take the card in the order operations arrived, perform the reads that
  /// precede consent, then call `prerequisitesComplete` (§8.2 item 2).
  case inspectPrerequisites
}
