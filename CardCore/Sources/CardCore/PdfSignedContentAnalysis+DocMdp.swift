// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Certification `DocMDP` permission inspection for
/// `PdfSignedContentAnalysis` (ISO 32000-1 §12.8.2.2.2).
extension PdfSignedContentAnalysis {
  /// Parsed list of direct or indirect dictionaries inside a PDF array.
  private struct ParsedDictionaryArray {
    /// Failed parse result.
    static let invalid = Self(isValid: false, elements: [])

    /// Whether the array syntax and indirect targets were valid.
    let isValid: Bool

    /// Resolved dictionary texts in order.
    let elements: [String]
  }

  /// Default `DocMDP` permission when `/P` is omitted in
  /// `/TransformParams` (ISO 32000-1 Table 254).
  private static let defaultDocMdp = 2

  /// Maximum defined `DocMDP` `/P` value (ISO 32000-1 Table 254).
  private static let maximumDocMdpPermission = 3

  /// Whether any certification signature in `index` sets no-changes
  /// `DocMDP` permission.
  internal static func hasNoChangesDocMdp(
    in index: PdfDocumentIndex,
    document: Data
  ) -> Bool {
    if let root = index.verifiedReference(named: "/Root", in: index.trailer),
      let catalog = index.comparisonBody(of: root, in: document),
      let perms = Self.resolvedDictionaryText(
        named: "Perms", in: catalog, index: index, document: document
      ),
      let docMdpSig = Self.resolvedDictionaryText(
        named: "DocMDP", in: perms, index: index, document: document
      ),
      Self.signatureCarriesNoChangesDocMdp(
        in: docMdpSig, index: index, document: document
      )
    {
      return true
    }
    for number in index.locations.keys.sorted() {
      guard
        let body = index.comparisonBody(of: number, in: document),
        Self.looksLikeSignatureDictionary(body),
        Self.signatureCarriesNoChangesDocMdp(
          in: body, index: index, document: document
        )
      else {
        continue
      }
      return true
    }
    return false
  }

  /// Whether `body` is a signature dictionary candidate rather than an
  /// unrelated XObject or annotation dictionary.
  private static func looksLikeSignatureDictionary(_ body: String) -> Bool {
    guard
      !PdfTypeEntry.hasStream(body),
      let syntax = PdfTypeEntry.dictionarySyntax(of: body)
    else {
      return false
    }
    if PdfTypeEntry.value(of: "Type", in: body) == "/Sig" {
      return true
    }
    return syntax.entry(named: "ByteRange") != nil
      && syntax.entry(named: "Contents") != nil
  }

  /// Checks whether a signature dictionary declares no-changes `DocMDP`
  /// permission in its `/Reference` list.
  private static func signatureCarriesNoChangesDocMdp(
    in signatureBody: String,
    index: PdfDocumentIndex,
    document: Data
  ) -> Bool {
    guard
      let syntax = PdfTypeEntry.dictionarySyntax(of: signatureBody),
      let refEntry = syntax.entry(named: "Reference")
    else {
      return false
    }
    let rawArray = syntax.value(of: refEntry)
    let arrayText: String
    if let reference = try? PdfValidationStore.ValueParser.reference(
      in: rawArray
    ) {
      guard
        index.locations[reference.number]?.generation == reference.generation,
        let body = index.comparisonBody(of: reference.number, in: document)
      else {
        return true
      }
      arrayText = body
    } else {
      arrayText = rawArray
    }
    let parsed = Self.dictionaryElements(
      inArray: arrayText, index: index, document: document
    )
    guard parsed.isValid else { return true }
    for sigRef in parsed.elements
    where PdfTypeEntry.value(of: "TransformMethod", in: sigRef) == "/DocMDP" {
      if Self.sigRefRequiresNoChanges(sigRef, index: index, document: document) {
        return true
      }
    }
    return false
  }

  /// Evaluates `/TransformParams` on a single `DocMDP` `/SigRef` entry.
  private static func sigRefRequiresNoChanges(
    _ sigRef: String,
    index: PdfDocumentIndex,
    document: Data
  ) -> Bool {
    guard let refSyntax = PdfTypeEntry.dictionarySyntax(of: sigRef) else {
      return true
    }
    guard refSyntax.entry(named: "TransformParams") != nil else {
      return false
    }
    guard
      let params = Self.resolvedDictionaryText(
        named: "TransformParams", in: sigRef, index: index, document: document
      ),
      let paramsSyntax = PdfTypeEntry.dictionarySyntax(of: params)
    else {
      return true
    }
    guard let permissionEntry = paramsSyntax.entry(named: "P") else {
      return Self.defaultDocMdp == PdfValues.docMdpNoChangesPermission
    }
    let rawPermission = paramsSyntax.value(of: permissionEntry)
    let permission: Int?
    if let direct = PdfValidationStore.TypedValues.unsignedInteger(
      in: rawPermission
    ) {
      permission = direct
    } else if let ref = try? PdfValidationStore.ValueParser.reference(
      in: rawPermission
    ),
      index.locations[ref.number]?.generation == ref.generation,
      let resolved = index.comparisonBody(of: ref.number, in: document)
    {
      permission = PdfValidationStore.TypedValues.unsignedInteger(in: resolved)
    } else {
      permission = nil
    }
    guard
      let permission,
      permission >= PdfValues.docMdpNoChangesPermission,
      permission <= Self.maximumDocMdpPermission
    else {
      return true
    }
    return permission == PdfValues.docMdpNoChangesPermission
  }

  /// Parses an array of direct or indirect dictionaries.
  private static func dictionaryElements(
    inArray text: String,
    index: PdfDocumentIndex,
    document: Data
  ) -> ParsedDictionaryArray {
    guard let data = text.data(using: .isoLatin1) else { return .invalid }
    var parser = PdfValidationStore.ValueParser(data)
    parser.skipTrivia()
    guard parser.consume("[") else { return .invalid }
    var results: [String] = []
    while true {
      parser.skipTrivia()
      if parser.consume("]") {
        guard (try? parser.requireEnd()) != nil else { return .invalid }
        return ParsedDictionaryArray(isValid: true, elements: results)
      }
      guard
        let element = Self.nextDictionaryElement(
          parser: &parser, data: data, index: index, document: document
        )
      else {
        return .invalid
      }
      results.append(element)
    }
  }

  /// Reads one direct or indirect dictionary element from an array.
  private static func nextDictionaryElement(
    parser: inout PdfValidationStore.ValueParser,
    data: Data,
    index: PdfDocumentIndex,
    document: Data
  ) -> String? {
    if parser.has("<<") {
      let start = parser.offset
      guard (try? parser.dictionary()) != nil else { return nil }
      return PdfValidationStore.ValueLexemes.text(
        data.subdata(in: start..<parser.offset)
      )
    }
    guard
      let numRange = try? parser.atom(),
      let number = PdfValidationStore.ValueLexemes.unsignedInteger(
        data.subdata(in: numRange)
      )
    else {
      return nil
    }
    parser.skipTrivia()
    guard
      let genRange = try? parser.atom(),
      PdfValidationStore.ValueLexemes.unsignedInteger(
        data.subdata(in: genRange)
      ) != nil
    else {
      return nil
    }
    parser.skipTrivia()
    guard
      let markerRange = try? parser.atom(),
      PdfValidationStore.ValueLexemes.text(data.subdata(in: markerRange))
        == "R"
    else {
      return nil
    }
    return index.comparisonBody(of: number, in: document)
  }
}
