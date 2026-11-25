// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore
@testable import RefineIDTestHost

/// App-level Estonian eID tests covering three-try retry health, macOS
/// attempts-bar formatting, and EU Trusted List document-signing anchors.
@MainActor
@Suite(.serialized, SharedDemoStateScope())
internal struct EstonianEidAppTests {
  private static let estonianAllowance: UInt8 = 3
  private static let belowFloorAttempts: UInt8 = 2
  private static let aboveEstonianAllowance: UInt8 = 4

  @Test
  internal func threeTryCardIsPristineAtThreeAndCriticalAtTwo() throws {
    let three = try #require(RetryCount(attemptsRemaining: Self.estonianAllowance))
    let two = try #require(RetryCount(attemptsRemaining: Self.belowFloorAttempts))
    let four = try #require(RetryCount(attemptsRemaining: Self.aboveEstonianAllowance))
    let health = CredentialRetryHealth.shared
    defer { health.clear() }

    health.update(
      CredentialProbeReport(
        pin1: .remaining(three),
        pin2: .remaining(three),
        puk: .remaining(three),
        pristineAllowance: Self.estonianAllowance
      )
    )
    #expect(health.level == .pristine)
    #expect(health.recovery == nil)

    health.update(
      CredentialProbeReport(
        pin1: .remaining(two),
        pin2: .remaining(three),
        puk: .remaining(three),
        pristineAllowance: Self.estonianAllowance
      )
    )
    #expect(health.level == .critical)

    health.update(
      CredentialProbeReport(
        pin1: .remaining(four),
        pin2: .remaining(three),
        puk: .remaining(three),
        pristineAllowance: Self.estonianAllowance
      )
    )
    #expect(health.level == nil)
  }

  #if os(macOS)
    @Test
    internal func readingsBelowFullHidesFullThreeTryCountersAndMarksAllowance() throws {
      let three = try #require(RetryCount(attemptsRemaining: Self.estonianAllowance))
      let two = try #require(RetryCount(attemptsRemaining: Self.belowFloorAttempts))

      let fullReport = CredentialProbeReport(
        pin1: .remaining(three),
        pin2: .remaining(three),
        puk: .remaining(three),
        pristineAllowance: Self.estonianAllowance
      )
      #expect(CardManagementView.readingsBelowFull(fullReport).isEmpty)

      let degradedReport = CredentialProbeReport(
        pin1: .remaining(two),
        pin2: .remaining(three),
        puk: .remaining(three),
        pristineAllowance: Self.estonianAllowance
      )
      let readings = CardManagementView.readingsBelowFull(degradedReport)
      #expect(readings.count == 1)
      #expect(readings.first?.pristineAllowance == Self.estonianAllowance)
      #expect(readings.first?.outcome == .remaining(two))
    }
  #endif

  @Test
  internal func trustedListIssuingAnchorPermitsEstonianSignerAndRefusesUnrelated() throws {
    let fixture = try CollectorRevocationFixtures.make()
    let unrelated = try SignerCertificateFixtures.makeSigner(for: .rsaSha256)
    let anchor = try #require(
      TrustAnchor(
        certificate: fixture.issuerCertificate,
        role: .certificateIssuing,
        granted: [.unbounded]
      )
    )
    let trustAnchors = TrustAnchors(
      anchors: [anchor],
      fetchedAt: fixture.currentTime,
      listsValidUntil: nil
    )

    let matched = ValidationMaterialCollector.signerAnchors(
      for: fixture.documentSignerCertificate,
      trustedListAnchors: trustAnchors,
      at: fixture.currentTime
    )
    #expect(matched.contains(fixture.issuerCertificate))
    #expect(SignatureLevelPolicy.longTermOnly.signerRefusal(anchors: matched) == nil)

    let unmatched = ValidationMaterialCollector.signerAnchors(
      for: unrelated.certificate,
      trustedListAnchors: trustAnchors,
      at: fixture.currentTime
    )
    #expect(unmatched.isEmpty)
    #expect(
      SignatureLevelPolicy.longTermOnly.signerRefusal(anchors: unmatched)
        == .trustAnchorUnavailable
    )
  }
}
