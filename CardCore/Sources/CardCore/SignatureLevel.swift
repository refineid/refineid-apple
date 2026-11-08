// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The baseline level a signature was verified to reach
/// (ETSI EN 319 142-1 and EN 319 132-1, clause 6).
///
/// Each level holds only when every level below it holds, and only as
/// far as this verifier established it from the document: an archive
/// timestamp it cannot recompute, or validation data that does not
/// answer the signer's path, leaves the signature at the level below.
public enum SignatureLevel: Sendable, Equatable {
  /// The signature verifies over intact signed data: B-B.
  case basic

  /// The document carries the validation data that answers the
  /// signer's path: B-LT.
  case longTerm

  /// An anchored archive timestamp covers the signature and its
  /// validation data: B-LTA.
  case longTermArchival

  /// An anchored timestamp proves when the signature existed: B-T.
  case timestamped

  /// The name of B-B in the baseline profiles.
  public static let basicLabel = "B-B"

  /// The name of B-T.
  public static let timestampedLabel = "B-T"

  /// The name of B-LT.
  public static let longTermLabel = "B-LT"

  /// The name of B-LTA.
  public static let longTermArchivalLabel = "B-LTA"

  /// The level's name in the baseline profiles.
  public var label: String {
    switch self {
    case .basic:
      Self.basicLabel

    case .timestamped:
      Self.timestampedLabel

    case .longTerm:
      Self.longTermLabel

    case .longTermArchival:
      Self.longTermArchivalLabel
    }
  }

  /// The highest level the established facts reach, nil when the
  /// signature does not verify over intact data.
  internal static func reached(
    verifies: Bool,
    timestamped: Bool,
    carriesValidationData: Bool,
    archived: Bool
  ) -> Self? {
    guard verifies else { return nil }
    guard timestamped else { return .basic }
    guard carriesValidationData else { return .timestamped }
    return archived ? .longTermArchival : .longTerm
  }
}
