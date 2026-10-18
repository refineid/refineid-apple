// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The cases are transcribed in the order the formal model lists them, so the
// tables read line for line against the document. Alphabetising them would
// break the correspondence the bidirectional conformance test protects.
// swiftlint:disable sorted_enum_cases

/// Pairing component state.
///
/// A pairing instance exists per stored or in-progress peer relationship;
/// `unpaired` is the absence of one. Raw values are the formal model's names.
internal enum PairingState: String, CaseIterable, Sendable {
  case unpaired = "unpaired"
  /// Requester only.
  case offerActive = "offer_active"
  case handshaking = "handshaking"
  case confirming = "confirming"
  /// The record is stored; the peer's `pairing.stored` is awaited.
  case storageConfirming = "storage_confirming"
  case pairedDisconnected = "paired_disconnected"
  case pairedConnected = "paired_connected"
  case revoked = "revoked"

  /// Whether a pairing record is stored in this state.
  ///
  /// An authenticated protocol violation revokes a stored pairing but only
  /// aborts an attempt that has not stored one.
  internal var holdsStoredPairing: Bool {
    switch self {
    case .storageConfirming, .pairedDisconnected, .pairedConnected:
      true

    case .unpaired, .offerActive, .handshaking, .confirming, .revoked:
      false
    }
  }
}

// swiftlint:enable sorted_enum_cases
