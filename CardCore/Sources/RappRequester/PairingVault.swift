// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The stored pairings a click off forgets, as the forgetting reads and
/// changes them.
///
/// The app's vault holds them in the keychain behind RAPP's own record
/// format; the forgetting needs only these five questions, so it can run
/// against a vault that keeps them anywhere.
public protocol PairingVault: Sendable {
  /// The pairings stored now, forgotten ones excluded.
  func activePairIDs() throws -> [Data]

  /// When the pairing `pairID` was made, in milliseconds since the Unix
  /// epoch.
  func createdAtMs(of pairID: Data) throws -> UInt64?

  /// When the pairing `pairID` was marked forgotten, or nil while it still
  /// serves.
  func forgottenAtMs(of pairID: Data) throws -> UInt64?

  /// Marks the pairing `pairID` forgotten at `forgottenAtMs`: it serves
  /// nothing more and keeps its key only for the `pairing_revoked` close.
  func forget(_ pairID: Data, at forgottenAtMs: UInt64) throws

  /// Destroys the pairing `pairID` and its key.
  func destroy(_ pairID: Data) throws
}
