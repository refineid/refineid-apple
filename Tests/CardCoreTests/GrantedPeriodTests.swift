// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// The granted periods a status history yields (TS 119 612 clauses
/// 5.5.4 and 5.6, annex J).
@Suite
internal struct GrantedPeriodTests {
  /// Seconds in a day.
  private static let day: TimeInterval = 86_400

  /// The end of the Directive regime.
  private static let regimeEnd = TrustService.directiveRegimeEnd

  /// A time a year before the regime ended.
  private static let directiveTime = Self.regimeEnd.addingTimeInterval(-365 * Self.day)

  /// A time a year after the regime ended.
  private static let regulationTime = Self.regimeEnd.addingTimeInterval(365 * Self.day)

  /// A time two years after the regime ended.
  private static let laterTime = Self.regimeEnd.addingTimeInterval(2 * 365 * Self.day)

  private static func entry(
    _ status: TrustService.Status,
    _ since: Date,
    _ kind: TrustService.Kind = .qualifiedCertificates
  ) -> TrustService.StatusEntry {
    TrustService.StatusEntry(status: status, since: since, kind: kind)
  }

  /// A service of the current entry's kind with `history`, newest
  /// first as lists write it.
  private static func service(
    _ current: TrustService.StatusEntry,
    _ history: [TrustService.StatusEntry]
  ) -> TrustService {
    TrustService(
      provider: "p", name: "s", kind: current.kind, certificates: [Data("c".utf8)],
      unreadableCertificates: 0, current: current, history: history)
  }

  @Test
  internal func aPeriodEndingBeforeItStartsIsRefused() {
    #expect(GrantedPeriod(start: Self.regulationTime, until: Self.directiveTime) == nil)
    let period = GrantedPeriod(start: Self.directiveTime, until: Self.regulationTime)
    #expect(period?.covers(Self.regimeEnd) == true)
    #expect(period?.covers(Self.laterTime) == false)
    #expect(GrantedPeriod.unbounded.covers(.distantFuture))
    #expect(TrustAnchor(certificate: Data(), role: .timeStamping, granted: []) == nil)
  }

  @Test
  internal func anEntryOfAnotherServiceTypeClosesAGrantedPeriod() {
    let service = Self.service(
      Self.entry(.granted, Self.laterTime),
      [
        Self.entry(.granted, Self.regulationTime, .other("x")),
        Self.entry(.granted, Self.directiveTime),
      ])
    #expect(
      service.grantedPeriods == [
        GrantedPeriod(start: Self.directiveTime, until: Self.regulationTime),
        GrantedPeriod(start: Self.laterTime, until: nil),
      ])
  }

  @Test
  internal func aDirectiveStatusGrantsACertificateServiceUntilTheRegimeEnded() {
    let supervisedThenWithdrawn = Self.service(
      Self.entry(.withdrawn, Self.laterTime), [Self.entry(.underSupervision, Self.directiveTime)])
    #expect(
      supervisedThenWithdrawn.grantedPeriods == [
        GrantedPeriod(start: Self.directiveTime, until: Self.regimeEnd)
      ])
    let accreditedLater = Self.service(Self.entry(.accredited, Self.regulationTime), [])
    #expect(accreditedLater.grantedPeriods.isEmpty)
    let supervisedStamping = Self.service(
      Self.entry(.underSupervision, Self.directiveTime, .qualifiedTimeStamps), [])
    #expect(supervisedStamping.grantedPeriods.isEmpty)
    let withdrawnOnly = Self.service(Self.entry(.withdrawn, Self.directiveTime), [])
    #expect(withdrawnOnly.grantedPeriods.isEmpty)
    #expect(withdrawnOnly.anchors.isEmpty)
  }

  @Test
  internal func ofStatusesAtOneInstantTheMostRecentCounts() {
    let withdrawnLast = Self.service(
      Self.entry(.withdrawn, Self.regulationTime), [Self.entry(.granted, Self.regulationTime)])
    #expect(withdrawnLast.grantedPeriods.isEmpty)
    let grantedLast = Self.service(
      Self.entry(.granted, Self.regulationTime),
      [Self.entry(.withdrawn, Self.regulationTime), Self.entry(.granted, Self.directiveTime)])
    #expect(
      grantedLast.grantedPeriods == [
        GrantedPeriod(start: Self.directiveTime, until: Self.regulationTime),
        GrantedPeriod(start: Self.regulationTime, until: nil),
      ])
  }

  @Test
  internal func theStatusIdentifiersRoundTrip() {
    for status in TrustService.Status.allCases {
      #expect(TrustService.Status(uri: status.uri) == status)
    }
    #expect(TrustService.Status(uri: TrustedListElement.statusPrefix + "unknown") == nil)
    #expect(
      TrustService.Kind(uri: TrustedListElement.qualifiedCertificatesType) == .qualifiedCertificates
    )
    #expect(TrustService.Kind(uri: "urn:other") == .other("urn:other"))
  }
}
