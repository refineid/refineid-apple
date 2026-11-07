// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A pointer to another list (TS 119 612 clause 5.3.13).
public struct TrustedListPointer: Sendable, Equatable {
  /// The form a pointer says the list it points at takes.
  public enum Format: Sendable, Equatable {
    /// Another form, such as the human-readable PDF, or none stated.
    case other

    /// The machine-processable XML list.
    case xml
  }

  /// Where the list is published, an HTTP or HTTPS URL; nil when the
  /// location is not one.
  public let location: String?

  /// The territory of the list pointed at.
  public let territory: String

  /// The declared type of the list pointed at; nil for a type the
  /// reader does not read.
  public let kind: TrustedList.Kind?

  /// The declared form of the list pointed at.
  public let format: Format

  /// The certificates entitled to sign the list pointed at.
  public let signers: [Data]

  /// How many of the pointer's certificates did not parse and were left
  /// out: a list signed under one of them does not read.
  public let unreadableSigners: Int

  /// Whether this pointer names a machine-processable national list:
  /// the ones `TrustedLists.read` follows.
  public var namesNationalList: Bool {
    kind == .euGeneric && format == .xml
  }

  /// Exactly these fields.
  internal init(
    location: String?,
    territory: String,
    kind: TrustedList.Kind?,
    format: Format,
    signers: [Data],
    unreadableSigners: Int
  ) {
    self.location = location
    self.territory = territory
    self.kind = kind
    self.format = format
    self.signers = signers
    self.unreadableSigners = unreadableSigners
  }
}
