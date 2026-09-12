// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import AppKit
import Foundation
import Testing

@testable import RefineID

/// Direct user-facing explanations for failures after the card signs.
@Suite
internal struct SignDocumentModelTests {
  private enum EvidenceFailure: Error {
    case unavailable
  }

  private static let stampCertificate = Data("stamp-certificate".utf8)

  /// A tiny synthetic signature image with ink surrounded by paper.
  private static func handwritingImage() throws -> Data {
    let side = 4
    let image = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side,
        pixelsHigh: side,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    )
    for across in 0..<side {
      for upward in 0..<side {
        let isInk = (1...2).contains(across) && (1...2).contains(upward)
        image.setColor(isInk ? .black : .white, atX: across, y: upward)
      }
    }
    return try #require(image.representation(using: .png, properties: [:]))
  }

  @Test
  @MainActor
  internal func validationFailureExplainsThatNoFileWasWritten() {
    let message = SignDocumentModel.message(
      for: DocumentSigner.Failure.validation(EvidenceFailure.unavailable)
    )

    #expect(
      message
        == String(
          localized: "error.validation",
          defaultValue:
            "Authenticated certificate and revocation evidence could not be collected.",
          table: "DocumentSigning"
        )
    )
  }

  @Test
  @MainActor
  internal func certificateIdentityProducesAStampWithoutHandwriting() throws {
    let model = SignDocumentModel()
    model.applyStampOutcome(
      .mark(
        CardMaintenance.Mark(
          bytes: nil,
          certificate: Self.stampCertificate,
          name: "Example Person",
          identifier: "TEST-IDENTIFIER"
        )
      )
    )

    let mark = try #require(model.stampMark())
    #expect(mark.operators.contains("0.0000 5.0000 cm"))
    #expect(mark.operators.contains("0.0000 -10.0000 cm"))
    // The note is localized, so it is compared against the same string
    // the model builds rather than an English fragment: a fragment
    // asserts the machine's language, and this test is about which note
    // was chosen.
    #expect(
      model.stampFailure
        == String(
          localized:
            "No handwritten signature; the stamp will show the certificate identity."
        )
    )
    #expect(
      model.visibleStamp(on: Data())?.signerCertificate
        == Self.stampCertificate
    )
  }

  @Test
  @MainActor
  internal func failedOrClearedReadCannotReuseAStampedIdentity() async {
    let model = SignDocumentModel()
    let identity = CardMaintenance.SignatureOutcome.mark(
      CardMaintenance.Mark(
        bytes: nil,
        certificate: Self.stampCertificate,
        name: "Example Person",
        identifier: "TEST-IDENTIFIER"
      )
    )

    model.applyStampOutcome(identity)
    #expect(model.stampMark() != nil)
    model.applyStampOutcome(.wrongAccessNumber)
    #expect(model.stampMark() == nil)

    model.applyStampOutcome(identity)
    model.applyStampOutcome(.noCard)
    #expect(model.stampMark() == nil)

    model.applyStampOutcome(identity)
    model.applyStampOutcome(.absent)
    #expect(model.stampMark() == nil)

    model.applyStampOutcome(identity)
    model.applyStampOutcome(.imageUnreadable)
    #expect(model.stampMark() == nil)

    model.applyStampOutcome(identity)
    let partiallyTypedAccessNumber = "123"
    await model.readStamp(
      accessNumber: partiallyTypedAccessNumber,
      style: .signatureAndIdentity
    )
    #expect(model.stampMark() == nil)

    model.applyStampOutcome(identity)
    model.clear()
    #expect(model.stampMark() == nil)
  }

  @Test
  @MainActor
  internal func malformedHandwritingCannotLeaveAnIdentityStamp() {
    let model = SignDocumentModel()
    model.applyStampOutcome(
      .mark(
        CardMaintenance.Mark(
          bytes: Data("not an image".utf8),
          certificate: Self.stampCertificate,
          name: "Example Person",
          identifier: "TEST-IDENTIFIER"
        )
      )
    )

    #expect(model.stampMark() == nil)
    #expect(
      model.stampFailure == String(localized: "The signature image could not be read.")
    )
  }

  @Test
  @MainActor
  internal func validHandwritingKeepsTheCertificateBinding() throws {
    let model = SignDocumentModel()
    model.applyStampOutcome(
      .mark(
        CardMaintenance.Mark(
          bytes: try Self.handwritingImage(),
          certificate: Self.stampCertificate,
          name: "Example Person",
          identifier: "TEST-IDENTIFIER"
        )
      )
    )

    let stamp = try #require(model.visibleStamp(on: Data()))
    #expect(stamp.signerCertificate == Self.stampCertificate)
    #expect(stamp.mark.operators.contains("-45.0000 -6.0000 m"))
    #expect(model.stampFailure == nil)
  }

  @Test
  @MainActor
  internal func changingOrCompletingADocumentClearsTheStampIdentity() {
    let model = SignDocumentModel()
    let identity = CardMaintenance.SignatureOutcome.mark(
      CardMaintenance.Mark(
        bytes: nil,
        certificate: Self.stampCertificate,
        name: "Example Person",
        identifier: "TEST-IDENTIFIER"
      )
    )

    model.applyStampOutcome(identity)
    model.accept(URL.temporaryDirectory.appendingPathComponent("next.pdf"))
    #expect(model.stampMark() == nil)

    model.applyStampOutcome(identity)
    let destination = URL.temporaryDirectory.appendingPathComponent("signed.pdf")
    model.complete(with: destination)
    #expect(model.stampMark() == nil)
    #expect(model.signed == destination)
  }

  @Test
  @MainActor
  internal func cardRemovalClearsFailureButKeepsTheChosenDocument() {
    let model = SignDocumentModel()
    let source = URL.temporaryDirectory.appendingPathComponent("waiting.pdf")
    model.accept(source)
    model.report("A card-bound failure")
    model.applyStampOutcome(
      .mark(
        CardMaintenance.Mark(
          bytes: nil,
          certificate: Self.stampCertificate,
          name: "Example Person",
          identifier: "TEST-IDENTIFIER"
        )
      )
    )

    model.cardRemoved()

    #expect(model.failure == nil)
    #expect(model.pending == source)
    #expect(model.stampMark() == nil)
  }

  @Test
  internal func qualifiedCertificateBindingRequiresTheExactDer() {
    let other = Data("other-certificate".utf8)

    #expect(
      CardMaintenance.qualifiedCertificate(
        Self.stampCertificate, matches: Self.stampCertificate
      )
    )
    #expect(
      !CardMaintenance.qualifiedCertificate(
        other, matches: Self.stampCertificate
      )
    )
    #expect(CardMaintenance.qualifiedCertificate(other, matches: nil))
  }

  @Test
  @MainActor
  internal func signerChangeExplainsThatNoFileWasWritten() {
    let message = SignDocumentModel.message(
      for: DocumentSigner.Failure.stampSignerChanged
    )

    #expect(
      message
        == String(
          localized: "error.cardChanged",
          defaultValue: "The signing card changed. Nothing was written.",
          table: "DocumentSigning"
        )
    )
  }
}
