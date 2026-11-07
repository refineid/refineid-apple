// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import Foundation
  import Testing

  @testable import CardCore
  @testable import RefineIDTestHost

  /// Release builds make only long-term signatures; development builds
  /// keep the level they reached and say so.
  @Suite
  internal struct SignatureLevelPolicyTests {
    private static let source = URL(fileURLWithPath: "/documents/Agreement.pdf")

    /// An instant standing in for the signature timestamp.
    private static let instant = Date(timeIntervalSinceReferenceDate: 0)

    /// The separator between a PIN's name and its number.
    private static let noBreakSpace = "\u{00A0}"

    /// The number in Signature PIN 2's name.
    private static let pin2Number = "2"

    @Test
    internal func releaseRefusesASignerWithoutAnAnchorBeforePin2() throws {
      let anchor = try SignerCertificateFixtures.makeSigner(
        for: .rsaSha256, certificateProfile: .certificateAuthority
      ).certificate
      #expect(
        SignatureLevelPolicy.longTermOnly.signerRefusal(anchors: [])
          == .trustAnchorUnavailable
      )
      #expect(SignatureLevelPolicy.longTermOnly.signerRefusal(anchors: [anchor]) == nil)
    }

    @Test
    internal func releaseKeepsNothingBelowLongTerm() {
      #expect(!SignatureLevelPolicy.longTermOnly.keepsBelowLongTerm)
    }

    @Test
    internal func developmentBuildKeepsTheLevelReached() {
      #expect(SignatureLevelPolicy.forBuild == .highestReached)
      #expect(SignatureLevelPolicy.highestReached.keepsBelowLongTerm)
      #expect(SignatureLevelPolicy.highestReached.signerRefusal(anchors: []) == nil)
    }

    @Test
    internal func releaseRefusalNamesItsReasonAndThePin() {
      let generic = DocumentSigningMessage.message(
        for: DocumentSigner.Failure.validation(
          ValidationMaterialCollector.Failure.chainCycle
        )
      )
      let anchor = DocumentSigningMessage.message(
        for: DocumentSigner.Failure.validation(
          ValidationMaterialCollector.Failure.trustAnchorUnavailable
        )
      )
      let issuer = DocumentSigningMessage.message(
        for: DocumentSigner.Failure.validation(
          ValidationMaterialCollector.Failure.issuerUnavailable
        )
      )
      #expect(Set([generic, anchor, issuer]).count == 3)
      #expect(anchor.contains(Self.noBreakSpace + Self.pin2Number))
    }

    @Test
    internal func aStageAboveTheTimestampNamesItsCause() {
      typealias Cause = BelowLongTermSignature.Cause
      let validation = { (failure: ValidationMaterialCollector.Failure) in
        Cause(afterTimestamp: DocumentSigner.Failure.validation(failure))
      }
      #expect(validation(.issuerUnavailable) == .issuerUnavailable)
      #expect(validation(.trustAnchorUnavailable) == .trustAnchorUnavailable)
      #expect(validation(.revocationUnavailable) == .revocationUnavailable)
      #expect(validation(.revoked(.documentSigner)) == .revoked)
      #expect(validation(.chainCycle) == .evidence)
      #expect(
        Cause(afterTimestamp: DocumentSigner.Failure.network(URLError(.timedOut)))
          == .archiveTimestamp
      )
    }

    @Test
    internal func aDevelopmentDocumentSaysWhatItIs() {
      let timestamped = BelowLongTermSignature(
        format: .pades, level: .timestamped, cause: .issuerUnavailable
      )
      let anchorless = BelowLongTermSignature(
        format: .pades, level: .timestamped, cause: .trustAnchorUnavailable
      )
      #expect(timestamped.levelName == "PAdES B-T")
      #expect(timestamped.nameMarker == "-dev-B-T")
      #expect(timestamped.notice.contains(timestamped.levelName))
      #expect(timestamped.notice.contains(timestamped.nameMarker))
      #expect(timestamped.notice != anchorless.notice)
      let basic = BelowLongTermSignature(
        format: .asice, level: .basic, cause: .signatureTimestamp
      )
      #expect(basic.levelName == "XAdES B-B")
      #expect(basic.nameMarker == "-dev-B-B")
    }

    @Test
    internal func aDevelopmentDocumentIsNamedByItsLevel() {
      let shortfall = BelowLongTermSignature(
        format: .pades, level: .timestamped, cause: .trustAnchorUnavailable
      )
      let signed = SignedDocument(
        bytes: Data("signed".utf8),
        signatureTimestampTime: Self.instant,
        belowLongTerm: shortfall
      )
      #expect(
        SignDocumentModel.suggestedName(
          for: Self.source, format: .pades, at: Self.instant, marker: signed.nameMarker
        ) == "Agreement" + SignedDocumentName.suffix(at: Self.instant) + "-dev-B-T.pdf"
      )
      let container = SignedDocumentName.suggested(
        sourceNames: ["Ledger.ods", "Notes.txt"],
        format: .asice,
        at: Self.instant,
        marker: signed.nameMarker
      )
      #expect(container.hasSuffix("-dev-B-T.asice"))
      let longTerm = SignedDocument(
        bytes: Data("signed".utf8), signatureTimestampTime: Self.instant
      )
      #expect(longTerm.nameMarker.isEmpty)
    }
  }

#endif
