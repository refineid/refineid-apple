// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

// The factory flags are absent on every result that is not an inspection, and
// absent is not false, so the interface carries them as optionals.
// swiftlint:disable discouraged_optional_boolean

/// The answer an operation produced.
///
/// The kind names which fields carry it; the rest stay absent.
public struct RappOperationResult: Equatable, Sendable {
  /// Which answer this result carries.
  public var kind: RappResultKind
  /// Whether PIN 1 is still the factory value.
  public var pin1Factory: Bool?
  /// Whether PIN 2 is still the factory value.
  public var pin2Factory: Bool?
  /// Attempts remaining on PIN 1, when the card reported them.
  public var pin1Attempts: UInt8?
  /// Attempts remaining on PIN 2, when the card reported them.
  public var pin2Attempts: UInt8?
  /// Attempts remaining on the unblocking code, when the card reported them.
  public var pukAttempts: UInt8?
  /// The cardholder's name, on an identity read.
  public var displayName: String?
  /// The cardholder's personal identifier, on an identity read.
  public var personId: String?
  /// The certificate or signature bytes, on a read or a signature.
  public var bytes: Data
  /// The ordered signatures of a batch, one per document.
  public var signatures: [Data]

  /// Creates a result carrying only the fields its kind defines.
  public init(
    kind: RappResultKind,
    pin1Factory: Bool? = nil,
    pin2Factory: Bool? = nil,
    pin1Attempts: UInt8? = nil,
    pin2Attempts: UInt8? = nil,
    pukAttempts: UInt8? = nil,
    displayName: String? = nil,
    personId: String? = nil,
    bytes: Data = Data(),
    signatures: [Data] = []
  ) {
    self.kind = kind
    self.pin1Factory = pin1Factory
    self.pin2Factory = pin2Factory
    self.pin1Attempts = pin1Attempts
    self.pin2Attempts = pin2Attempts
    self.pukAttempts = pukAttempts
    self.displayName = displayName
    self.personId = personId
    self.bytes = bytes
    self.signatures = signatures
  }
}

// swiftlint:enable discouraged_optional_boolean
