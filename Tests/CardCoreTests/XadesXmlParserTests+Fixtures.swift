// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// Signatures-file construction for the parser tests.
extension XadesXmlParserTests {
  /// Line length of wrapped base64 (RFC 7468 section 2).
  private static let wrapColumn = 64

  /// The line break placed between wrapped base64 lines.
  private static let wrapBreak = "\r\n"

  private static let signatureOpen = "<ds:Signature "
  private static let signatureClose = "</ds:Signature>"

  /// The parsed signatures of a signatures-file text.
  internal static func parse(_ document: String) -> [AsicVerification.ParsedSignature] {
    XadesXmlParser().parse(data: Data(document.utf8))
  }

  /// The references of a signature whose references all read.
  internal static func references(
    of parsed: AsicVerification.ParsedSignature
  ) -> [AsicVerification.ParsedReference] {
    guard case .complete(let references) = parsed.references else {
      Issue.record("A reference did not read")
      return []
    }
    return references
  }

  /// The one `ds:Signature` element of a signatures file.
  internal static func signatureElement(of document: String) throws -> String {
    let start = try #require(document.range(of: Self.signatureOpen))
    let end = try #require(document.range(of: Self.signatureClose, options: .backwards))
    return String(document[start.lowerBound..<end.upperBound])
  }

  /// A signatures file holding `elements` under one root.
  internal static func signaturesFile(_ elements: [String]) -> String {
    #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
      + #"<asic:XAdESSignatures xmlns:asic="\#(XadesSignature.namespaceAsic)">"# + "\n"
      + elements.joined(separator: "\n") + "\n"
      + "</asic:XAdESSignatures>\n"
  }

  /// `text` with `insertion` placed before the first `marker`.
  internal static func inserting(
    _ insertion: String, before marker: String, in text: String
  ) throws -> String {
    var out = text
    let range = try #require(out.range(of: marker))
    out.insert(contentsOf: insertion, at: range.lowerBound)
    return out
  }

  /// A signature over the sample objects carrying one SHA-384
  /// signature time-stamp.
  internal static func stampedDocument(
    authority: TimestampAuthorityFixture
  ) throws -> AsicVerificationTests.SignedDocument {
    try AsicVerificationTests.signedDocument(profile: .ecdsaP384) { signature in
      [
        try authority.token(
          imprint: XadesSignature.timestampDigest(signature),
          algorithm: DocumentDigestAlgorithm.sha384.algorithmIdentifier
        )
      ]
    }
  }

  /// `text` with the content of every `tag` element wrapped.
  internal static func wrappingContent(of tag: String, in text: String) -> String {
    var out = ""
    var rest = Substring(text)
    while let open = rest.range(of: "<\(tag)") {
      guard
        let openEnd = rest.range(of: ">", range: open.upperBound..<rest.endIndex),
        let close = rest.range(of: "</\(tag)>", range: openEnd.upperBound..<rest.endIndex)
      else {
        break
      }
      out += rest[rest.startIndex..<openEnd.upperBound]
      out += Self.wrapped(String(rest[openEnd.upperBound..<close.lowerBound]))
      out += rest[close.lowerBound..<close.upperBound]
      rest = rest[close.upperBound...]
    }
    return out + rest
  }

  /// `text` broken into lines of `wrapColumn` characters.
  private static func wrapped(_ text: String) -> String {
    var lines: [String] = []
    var rest = Substring(text)
    while !rest.isEmpty {
      lines.append(String(rest.prefix(Self.wrapColumn)))
      rest = rest.dropFirst(Self.wrapColumn)
    }
    return Self.wrapBreak + lines.joined(separator: Self.wrapBreak) + Self.wrapBreak
  }

  /// Expects two parsed signatures to carry the same fields.
  internal static func expectSameFields(
    _ actual: AsicVerification.ParsedSignature,
    _ expected: AsicVerification.ParsedSignature
  ) {
    #expect(actual.signedInfoRawXml == expected.signedInfoRawXml)
    #expect(actual.signatureValueRawXml == expected.signatureValueRawXml)
    #expect(actual.signedPropertiesRawXml == expected.signedPropertiesRawXml)
    #expect(actual.signedPropertiesId == expected.signedPropertiesId)
    #expect(actual.signatureValueId == expected.signatureValueId)
    #expect(actual.signatureValueBytes == expected.signatureValueBytes)
    #expect(actual.signerCertificateDer == expected.signerCertificateDer)
    #expect(actual.keyInfoCertificates == expected.keyInfoCertificates)
    #expect(actual.signatureMethod == expected.signatureMethod)
    #expect(actual.canonicalizationMethod == expected.canonicalizationMethod)
    let actualReferences = Self.references(of: actual)
    let expectedReferences = Self.references(of: expected)
    #expect(actualReferences.map(\.uri) == expectedReferences.map(\.uri))
    #expect(actualReferences.map(\.digestValue) == expectedReferences.map(\.digestValue))
    #expect(actual.signatureTimestampTokens == expected.signatureTimestampTokens)
    #expect(actual.certificateValues == expected.certificateValues)
    #expect(actual.ocspValues == expected.ocspValues)
    #expect(actual.crlValues == expected.crlValues)
    #expect(actual.isCounterSignature == expected.isCounterSignature)
  }
}
