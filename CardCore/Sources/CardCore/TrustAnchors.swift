// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The certificates a relying party trusts as path anchors, one set
/// per role (RFC 5280 section 6.1.1).
///
/// A certificate-issuing anchor ends the path of a document signer; a
/// time-stamping anchor ends the path of a time-stamp authority. A
/// certificate a document carries never becomes an anchor.
public struct TrustAnchors: Sendable {
  /// The anchors pinned in this application: the DVV roots for
  /// certificate issuing and the qualified time-stamping root the
  /// signing side asks.
  public static var pinned: Self {
    Self(
      certificateIssuing: PinnedTrustAnchors.certificateIssuing,
      timeStamping: PinnedTrustAnchors.timeStamping
    )
  }

  /// Anchors for the paths of document signers.
  public let certificateIssuing: [Data]

  /// Anchors for the paths of time-stamp authorities.
  public let timeStamping: [Data]

  /// Groups the anchors of the two roles.
  public init(certificateIssuing: [Data], timeStamping: [Data]) {
    self.certificateIssuing = certificateIssuing
    self.timeStamping = timeStamping
  }
}
