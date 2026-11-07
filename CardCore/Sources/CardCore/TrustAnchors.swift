// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The trust anchors a verdict is judged under, and when the lists they
/// came from were fetched (RFC 5280 section 6.1.1).
///
/// A certificate-issuing anchor ends the path of a document signer; a
/// time-stamping anchor ends the path of a time-stamp authority. A
/// certificate a document carries never becomes an anchor. The anchors
/// come from the EU trusted lists the shell fetches
/// (`init(trustedLists:)`); the software ships no anchor of its own.
public struct TrustAnchors: Sendable, Equatable {
  /// No anchor at all: nothing can be anchored.
  public static let empty = Self(anchors: [], fetchedAt: nil, listsValidUntil: nil)

  /// Every anchor.
  public let anchors: [TrustAnchor]

  /// When the shell fetched the lists the anchors came from; nil for
  /// anchors that come from no list.
  public let fetchedAt: Date?

  /// The earliest next update the lists the anchors came from
  /// announce.
  ///
  /// The anchors come from a stale list after it. Nil for anchors from
  /// no list, or from closed lists.
  public let listsValidUntil: Date?

  /// Exactly these anchors, fetched at `fetchedAt` from lists whose
  /// earliest next update is `listsValidUntil`.
  public init(anchors: [TrustAnchor], fetchedAt: Date?, listsValidUntil: Date?) {
    self.anchors = anchors
    self.fetchedAt = fetchedAt
    self.listsValidUntil = listsValidUntil
  }

  /// The anchors a relying party takes from `lists`: one per
  /// certificate of every qualified certificate-issuing and
  /// time-stamping service the national lists carry, granted for the
  /// periods its status history grants (`TrustService.grantedPeriods`),
  /// fetched at the lists' fetch time and valid until the earliest next
  /// update.
  public init(trustedLists lists: TrustedLists) {
    let listed = lists.national.compactMap { list in try? list.outcome.get() }
    self.init(
      anchors: listed.flatMap { list in list.services.flatMap(\.anchors) },
      fetchedAt: lists.fetchedAt,
      listsValidUntil: lists.validUntil
    )
  }

  /// The certificates trusted for `role` at `instant`.
  public func certificates(for role: TrustAnchor.Role, at instant: Date) -> [Data] {
    anchors.filter { anchor in anchor.isTrusted(for: role, at: instant) }.map(\.certificate)
  }

  /// Whether a list the anchors come from is past its next update at
  /// `now` (TS 119 612 clause 5.3.15).
  public func isStale(at now: Date) -> Bool {
    listsValidUntil.map { until in until < now } ?? false
  }
}
