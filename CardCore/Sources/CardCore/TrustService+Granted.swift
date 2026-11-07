// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The periods a service's status history grants, and the anchors it
/// yields.
extension TrustService {
  /// How far one status entry grants trust in a service's outputs.
  private enum Grant: Equatable {
    /// It grants nothing.
    case nothing

    /// It grants until a later status says otherwise.
    case openEnded

    /// It grants until a later status says otherwise, and at the latest
    /// until this instant.
    case until(Date)
  }

  /// A period being built: when it opened and the latest it may close.
  private struct OpenPeriod {
    let start: Date
    let until: Date?
  }

  /// The periods during which the service's status granted trust in
  /// its outputs (clauses 5.5.4, 5.5.5, 5.5.10 and 5.6, annex J).
  ///
  /// Every status is walked in time order: a period opens at a status
  /// that grants and closes at the next that does not, an entry of
  /// another service type than the current one included, or at the
  /// end a Directive status grants until; it stays open-ended while
  /// the current status grants. Of statuses starting at one instant
  /// the most recent fact counts last: the history, listed newest
  /// first, from its last entry to its first, then the current status.
  /// A period that closes at the instant it opened grants nothing and
  /// is left out.
  public var grantedPeriods: [GrantedPeriod] {
    let entries = (history.reversed() + [current]).enumerated()
      .sorted { lhs, rhs in
        lhs.element.since == rhs.element.since
          ? lhs.offset < rhs.offset : lhs.element.since < rhs.element.since
      }
      .map(\.element)
    var periods: [GrantedPeriod] = []
    var open: OpenPeriod?
    func close(_ period: OpenPeriod, at end: Date?) {
      guard end != period.start else { return }
      if let closed = GrantedPeriod(start: period.start, until: end) { periods.append(closed) }
    }
    for entry in entries {
      if let period = open, let until = period.until, until < entry.since {
        close(period, at: until)
        open = nil
      }
      switch (open, Self.grant(of: entry, for: kind)) {
      case (nil, .nothing):
        open = nil

      case (let period?, .nothing):
        close(period, at: entry.since)
        open = nil

      case (nil, .until(let until)):
        open = OpenPeriod(start: entry.since, until: until)

      case (nil, .openEnded):
        open = OpenPeriod(start: entry.since, until: nil)

      case (let period?, .until(let until)):
        open = OpenPeriod(start: period.start, until: until)

      case (let period?, .openEnded):
        open = OpenPeriod(start: period.start, until: nil)
      }
    }
    if let period = open {
      close(period, at: period.until)
    }
    return periods
  }

  /// The anchors this service yields: one per certificate, for the
  /// role its type names, granted for `grantedPeriods`; none for a
  /// type no anchor is taken from, and none for a service never
  /// granted.
  internal var anchors: [TrustAnchor] {
    guard let role = kind.anchorRole else { return [] }
    let periods = grantedPeriods
    return certificates.compactMap { certificate in
      TrustAnchor(certificate: certificate, role: role, granted: periods)
    }
  }

  /// What `entry` grants a service of `kind`.
  ///
  /// `granted` grants a qualified certificate or time-stamping service
  /// (clause 5.5.4). On a qualified certificate service the statuses
  /// of Directive 1999/93/EC that started before
  /// `directiveRegimeEnd` grant until then at the latest (annex J (a)),
  /// and nothing when they start later; on a qualified time-stamping
  /// service annex J (c) made them `withdrawn`. An entry recorded
  /// under another service type grants nothing.
  private static func grant(of entry: StatusEntry, for kind: Kind) -> Grant {
    guard entry.kind == kind else { return .nothing }
    switch (kind, entry.status) {
    case (.qualifiedCertificates, .granted), (.qualifiedTimeStamps, .granted):
      return .openEnded

    case (.qualifiedCertificates, let status) where status.isDirectiveGrant:
      return entry.since < Self.directiveRegimeEnd ? .until(Self.directiveRegimeEnd) : .nothing

    default:
      return .nothing
    }
  }
}
