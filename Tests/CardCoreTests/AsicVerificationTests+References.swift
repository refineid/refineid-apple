// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// A reference the verifier cannot recompute fails the document
/// integrity verdict.
extension AsicVerificationTests {
  /// A digest method no verifier here implements.
  private static let unknownDigestMethod = "urn:example:unknown-digest"

  private static let signedInfoOpen = "<ds:SignedInfo"
  private static let signedInfoClose = "</ds:SignedInfo>"
  private static let signedPropertiesOpen = "<xades:SignedProperties"
  private static let signedPropertiesClose = "</xades:SignedProperties>"
  private static let transformsOpen = "<ds:Transforms>"
  private static let transformsClose = "</ds:Transforms>\n"

  /// `URI` of the reference our writer points at its SignedProperties.
  private static var signedPropertiesUri: String {
    #"URI="\#(AsicVerification.sameDocumentUriPrefix)\#(XadesSignature.signedPropertiesId)""#
  }

  /// The text from `open` through `close` in `text`.
  private static func slice(
    of text: String, from open: String, through close: String
  ) throws -> Range<String.Index> {
    let start = try #require(text.range(of: open))
    let end = try #require(text.range(of: close, range: start.lowerBound..<text.endIndex))
    return start.lowerBound..<end.upperBound
  }

  /// The document with its SignedInfo edited and signed again by the
  /// same key, so the signature itself stays valid.
  private static func resigned(
    profile: CardKeyProfile,
    edit: (String) throws -> String
  ) throws -> String {
    let signed = try Self.signedDocument(profile: profile)
    var document = signed.document
    let range = try Self.slice(
      of: document, from: Self.signedInfoOpen, through: Self.signedInfoClose)
    let editedInfo = try edit(String(document[range]))
    document.replaceSubrange(range, with: editedInfo)
    let signature = try Self.xmlSignature(
      over: Data(editedInfo.utf8), identity: signed.identity, profile: profile)
    return document.replacingOccurrences(
      of: XadesSignature.signatureValueElement(signed.xmlSignature),
      with: XadesSignature.signatureValueElement(signature)
    )
  }

  @Test
  internal func resignedUnchangedSignedInfoStillVerifies() throws {
    let report = try Self.report(
      Self.container(document: Self.resigned(profile: .ecdsaP384) { $0 }))
    #expect(report.documentIntact)
    #expect(report.signatureValid)
  }

  @Test
  internal func removedSignedPropertiesIsNotIntact() throws {
    var document = try Self.signedDocument(profile: .ecdsaP384).document
    document.removeSubrange(
      try Self.slice(
        of: document, from: Self.signedPropertiesOpen, through: Self.signedPropertiesClose))

    let report = try Self.report(Self.container(document: document))
    #expect(report.signatureValid)
    #expect(!report.documentIntact)
    #expect(!report.coversWholeDocument)
  }

  @Test
  internal func alteredSignedPropertiesIsNotIntact() throws {
    let object = try #require(Self.sampleObjects().first)
    let original = "<xades:MimeType>\(object.mimeType)</xades:MimeType>"
    let document = try Self.signedDocument(profile: .rsa2048).document
    #expect(document.contains(original))
    let altered = document.replacingOccurrences(
      of: original, with: "<xades:MimeType>application/octet-stream</xades:MimeType>")

    let report = try Self.report(Self.container(document: altered))
    #expect(report.signatureValid)
    #expect(!report.documentIntact)
  }

  @Test
  internal func unknownSignedPropertiesDigestMethodIsNotIntact() throws {
    let document = try Self.resigned(profile: .ecdsaP384) { info in
      var edited = info
      let reference = try #require(edited.range(of: Self.signedPropertiesUri))
      let method = try #require(
        edited.range(
          of: XadesSignature.digestMethodSha384,
          range: reference.upperBound..<edited.endIndex))
      edited.replaceSubrange(method, with: Self.unknownDigestMethod)
      return edited
    }

    let report = try Self.report(Self.container(document: document))
    #expect(report.signatureValid)
    #expect(!report.documentIntact)
  }

  @Test
  internal func sameDocumentReferenceToAnotherElementIsNotIntact() throws {
    let document = try Self.resigned(profile: .ecdsaP384) { info in
      #expect(info.contains(Self.signedPropertiesUri))
      return info.replacingOccurrences(
        of: Self.signedPropertiesUri,
        with: #"URI="\#(AsicVerification.sameDocumentUriPrefix)\#(XadesSignature.signatureId)""#
      )
    }

    let report = try Self.report(Self.container(document: document))
    #expect(report.signatureValid)
    #expect(!report.documentIntact)
  }

  @Test
  internal func signedPropertiesReferenceWithoutItsTransformIsNotIntact() throws {
    let document = try Self.resigned(profile: .ecdsaP384) { info in
      var edited = info
      edited.removeSubrange(
        try Self.slice(of: edited, from: Self.transformsOpen, through: Self.transformsClose))
      return edited
    }

    let report = try Self.report(Self.container(document: document))
    #expect(report.signatureValid)
    #expect(!report.documentIntact)
  }
}
