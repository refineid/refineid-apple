// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are transcribed in the order the formal model lists them, so the
// tables read line for line against the document. Alphabetising them would
// break the correspondence the bidirectional conformance test protects.
// swiftlint:disable sorted_enum_cases

/// Pairing component state (RAPP v26.10.21 formal state model).
///
/// A pairing instance exists per stored or in-progress peer relationship;
/// `unpaired` is the absence of one. Raw values are the formal model's names.
internal enum PairingState: String, CaseIterable, Sendable {
  case unpaired = "unpaired"
  /// Custodian only.
  case offering = "offering"
  /// CPace.
  case exchanging = "exchanging"
  /// Noise_XXpsk3.
  case handshaking = "handshaking"
  case confirming = "confirming"
  case storageConfirming = "storage_confirming"
  case pairedDisconnected = "paired_disconnected"
  case pairedConnected = "paired_connected"
  /// Key kept for the pairing_revoked close.
  case revoking = "revoking"
  case revoked = "revoked"
}

// swiftlint:enable sorted_enum_cases
