// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineID

/// The shapes a pile of documents can take, and the names its outputs
/// are given.
@Suite
internal struct SignDocumentShapeTests {
  /// A pile of PDFs keeps the shape that signs each one in place.
  ///
  /// PDFs are signed one by one and stored one by one; the container
  /// is what a set of other file types has no alternative to. A pile
  /// of PDFs that could only take the container shape would have lost
  /// the ordinary way of signing several PDFs at once.
  @Test
  @MainActor
  internal func severalPdfsAreStillSignedOneByOne() {
    let pdfs = [
      URL(fileURLWithPath: "/documents/One.pdf"),
      URL(fileURLWithPath: "/documents/Two.pdf"),
      URL(fileURLWithPath: "/documents/Three.pdf"),
    ]
    #expect(StatusView.sharedFormat(for: pdfs) == .pades)
    // And the choice is genuinely offered, not merely defaulted: the
    // same pile can be sent into one container instead.
    #expect(SignatureFormat.available(for: pdfs[0]).contains(.asice))
  }

  /// One file type among PDFs leaves the container as the only shape.
  @Test
  @MainActor
  internal func aMixedPileCanOnlyTakeTheContainer() {
    let mixed = [
      URL(fileURLWithPath: "/documents/One.pdf"),
      URL(fileURLWithPath: "/documents/Ledger.ods"),
    ]
    #expect(StatusView.sharedFormat(for: mixed) == .asice)
  }

  /// A container's name always carries the signing instant, whether
  /// the holder kept the proposed suffix or typed over it.
  ///
  /// The panel proposes the suffix and the holder writes the
  /// beginning; a name that comes back with the suffix is kept as it
  /// is, and one where typing replaced it gets the same instant
  /// appended - stamped once either way.
  ///
  /// The suffix is read from the code rather than written out here.
  /// Half of it is the word for signing in the app's language, so a
  /// spelled-out English one asserts the machine's language and fails
  /// on a Finnish or Swedish one for a reason that has nothing to do
  /// with how a container is named. What must not move with the
  /// language is the instant, and that is asserted on its own.
  @Test
  @MainActor
  internal func aContainersWrittenNameCarriesTheInstantExactlyOnce() throws {
    let instant = try #require(
      ISO8601DateFormatter().date(from: "2026-08-12T14:30:12Z")
    )
    let suffix = SignDocumentModel.signedNameSuffix(at: instant)
    // The instant keeps the engineering form in every language: a name
    // mailed abroad still sorts and reads the same.
    #expect(suffix.contains("2026-08-12T14-30-12Z"))
    // Typed in front of the proposed suffix: kept, not stamped again.
    #expect(
      SignDocumentModel.stampedContainer(
        from: URL(fileURLWithPath: "/documents/kasa" + suffix + ".asice"),
        at: instant
      ).lastPathComponent == "kasa" + suffix + ".asice"
    )
    // Typed over the suffix: the same instant is appended.
    #expect(
      SignDocumentModel.stampedContainer(
        from: URL(fileURLWithPath: "/documents/kasa.asice"), at: instant
      ).lastPathComponent == "kasa" + suffix + ".asice"
    )
    // A name that arrives bare is stamped the same way.
    #expect(
      SignDocumentModel.stampedContainer(
        from: URL(fileURLWithPath: "/documents/kasa"), at: instant
      ).lastPathComponent == "kasa" + suffix + ".asice"
    )
    // One document keeps its own name, which is not a guess at all.
    #expect(
      SignDocumentModel.destination(
        for: URL(fileURLWithPath: "/documents/Agreement.odt"),
        at: instant,
        format: .asice
      ).lastPathComponent == "Agreement" + suffix + ".asice"
    )
  }
}
