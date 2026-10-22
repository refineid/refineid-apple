// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

@testable import RefineID

/// When the custodian's word on its card changes (RAPP v26.10.21 §8.4).
@Suite
internal struct CustodianCardReportTests {
  @Test("A servable card is present until an operation ends without it")
  internal func unattendedEndingReportsAbsentOnce() {
    var report = CustodianCardReport(servable: true)
    #expect(report.present)
    #expect(report.operationEndedUnattended() == .absent)
    #expect(!report.present)
    #expect(report.operationEndedUnattended() == nil)
    #expect(!report.present)
  }

  @Test("A card that cannot be served stays absent through a failure")
  internal func unservableCardStaysAbsent() {
    var report = CustodianCardReport(servable: false)
    #expect(!report.present)
    #expect(report.operationEndedUnattended() == nil)
    #expect(report.availabilityChanged(servable: false) == nil)
  }

  @Test("The next prime or coupling reports the card present again")
  internal func couplingAfterFailureReportsPresent() {
    var report = CustodianCardReport(servable: true)
    #expect(report.operationEndedUnattended() == .absent)
    #expect(report.availabilityChanged(servable: true) == .present)
    #expect(report.present)
    #expect(report.availabilityChanged(servable: true) == nil)
  }

  @Test("A card that answers reports present again")
  internal func answerAfterFailureReportsPresent() {
    var report = CustodianCardReport(servable: true)
    #expect(report.operationEndedUnattended() == .absent)
    #expect(report.cardAnswered() == .present)
    #expect(report.cardAnswered() == nil)
  }

  @Test("Losing the card after a failure changes no word; regaining it does")
  internal func availabilityAfterFailure() {
    var report = CustodianCardReport(servable: true)
    #expect(report.operationEndedUnattended() == .absent)
    #expect(report.availabilityChanged(servable: false) == nil)
    #expect(report.availabilityChanged(servable: true) == .present)
    #expect(report.availabilityChanged(servable: false) == .absent)
  }
}
