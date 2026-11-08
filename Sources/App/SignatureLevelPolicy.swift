// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What a build does with a signature whose long-term level is out of
/// reach.
///
/// The long-term level is the archival one for every format:
/// PAdES-B-LTA for a PDF and XAdES-B-LTA for an ASiC-E container. The build fixes the policy at compile time through
/// `forBuild`; nothing at run time selects it. Decision record in
/// `Documentation/decisions.md`.
internal enum SignatureLevelPolicy: Equatable, Sendable {
  /// Only a long-term signature leaves the signer. Anything less is
  /// refused with its reason, and nothing is saved.
  case longTermOnly

  #if DEBUG
    /// The highest baseline level reached is kept and named by its
    /// level, for development use.
    case highestReached
  #endif

  /// Release and TestFlight builds make only long-term signatures; a
  /// development build keeps what it reached.
  internal static var forBuild: Self {
    #if DEBUG
      .highestReached
    #else
      .longTermOnly
    #endif
  }

  /// Whether a document below the long-term level may leave the signer.
  internal var keepsBelowLongTerm: Bool {
    switch self {
    case .longTermOnly:
      false

    #if DEBUG
      case .highestReached:
        true
    #endif
    }
  }

  /// The refusal of a signer certificate whose path no approved anchor
  /// can end, decided from the certificate before PIN 2 is presented.
  ///
  /// `anchors` are the certificates the evidence walk would accept as
  /// the end of the signer path; with none, that walk is certain to
  /// fail with `trustAnchorUnavailable`. Nil when signing may go on.
  internal func signerRefusal(
    anchors: Set<Data>
  ) -> ValidationMaterialCollector.Failure? {
    guard !keepsBelowLongTerm, anchors.isEmpty else { return nil }
    return .trustAnchorUnavailable
  }
}
