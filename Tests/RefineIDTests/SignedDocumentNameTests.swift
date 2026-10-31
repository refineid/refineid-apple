// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import Foundation
  import Testing

  @testable import CardCore
  @testable import RefineIDTestHost

  /// Signed outputs are named by their best signature time.
  @Suite
  internal struct SignedDocumentNameTests {
    /// How far the document timestamp lies after the signature timestamp.
    private static let documentTimestampDelay: TimeInterval = 60

    /// An instant standing in for the clock.
    private static let clock = Date(timeIntervalSinceReferenceDate: 0)

    private static let source = URL(fileURLWithPath: "/documents/Agreement.pdf")

    /// GeneralizedTime as the generated authority writes it.
    private static func generalizedTimeFormatter() -> DateFormatter {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = "yyyyMMddHHmmss'Z'"
      return formatter
    }

    @Test
    internal func aSignatureTimestampNamesTheOutput() throws {
      let fixture = try DebugRevokedDocumentSigningFixture.make()
      let generated = try RfcTimestamp.generationTime(in: fixture.timestampToken)
      let signed = SignedDocument(
        bytes: fixture.timestamped.bytes,
        signatureTimestampTime: fixture.timestamped.signatureTimestampTime
      )
      #expect(fixture.timestamped.signatureTimestampTime == generated)
      #expect(signed.bestSignatureTime == generated)
      #expect(
        SignDocumentModel.suggestedName(
          for: Self.source, format: .pades, at: signed.bestSignatureTime
        ) == "Agreement" + SignedDocumentName.suffix(at: generated) + ".pdf"
      )
    }

    @Test
    internal func noSignatureTimestampNamesTheOutputByTheClock() {
      let signed = SignedDocument(untimestamped: Data("unsigned".utf8), clock: Self.clock)
      #expect(signed.bestSignatureTime == Self.clock)
      let name = SignedDocumentName.suggested(
        sourceNames: ["Ledger.ods", "Notes.txt"],
        format: .asice,
        at: signed.bestSignatureTime
      )
      #expect(name.contains(SignedDocumentName.suffix(at: Self.clock)))
    }

    /// A PDF carrying both a signature timestamp and a later document
    /// timestamp is named by the signature timestamp.
    @Test
    internal func aDocumentTimestampDoesNotNameTheOutput() throws {
      let fixture = try DebugRevokedDocumentSigningFixture.make()
      let signatureTime = try RfcTimestamp.generationTime(in: fixture.timestampToken)
      let formatter = Self.generalizedTimeFormatter()
      let documentTime = signatureTime.addingTimeInterval(Self.documentTimestampDelay)
      let prepared = try PdfIncrementalSigner.prepare(
        fixture.timestamped.bytes, revision: .documentTimestamp
      )
      let authority = try DebugTimestampAuthority.make()
      let documentToken = try authority.response(
        imprint: prepared.digest(.sha384),
        nonce: Data("document timestamp nonce".utf8),
        generationTime: formatter.string(from: documentTime)
      ).token
      let archived = try prepared.filled(with: documentToken)
      #expect(try RfcTimestamp.generationTime(in: documentToken) == documentTime)

      let product = DocumentSigner.Product(
        bytes: archived, completion: .archival, signature: fixture.timestamped
      )
      let signed = SignedDocument(
        bytes: product.bytes,
        signatureTimestampTime: product.signatureTimestampTime
      )
      #expect(signed.bestSignatureTime == signatureTime)
      let name = SignDocumentModel.suggestedName(
        for: Self.source, format: .pades, at: signed.bestSignatureTime
      )
      #expect(name.contains(SignedDocumentName.suffix(at: signatureTime)))
      #expect(!name.contains(SignedDocumentName.suffix(at: documentTime)))
    }
  }

#endif
