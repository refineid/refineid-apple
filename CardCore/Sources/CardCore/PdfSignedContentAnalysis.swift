// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What the revisions after a signed one change in a PDF.
///
/// The signed revision is indexed on its own and compared with the
/// newest view of the document, object by object, number by number. An
/// object whose body is the same in both views is untouched. A later
/// revision may, without changing what the signer saw, add a document
/// security store, certificates, OCSP responses and CRLs for it, a
/// signature or document timestamp and the widgets they need, metadata,
/// and cross-reference or object streams; it may give the catalog
/// `/DSS`, `/AcroForm` or `/Metadata`, append signature fields to the
/// form, and append annotations to a page.
///
/// Every other change is reported. A document that cannot be indexed is
/// reported as changed rather than trusted.
internal enum PdfSignedContentAnalysis {
  /// The entry names that differ between two dictionaries, and whether
  /// both could be read at all.
  private struct EntryDifferences {
    /// The names whose value is not the same in both.
    let names: Set<String>

    /// Whether both dictionaries could be parsed.
    let isReadable: Bool
  }

  /// The type markers an added object may carry.
  private static let allowedAdditionMarkers = [
    "/Type /XRef",
    "/Type /ObjStm",
    "/Type /DSS",
    "/Type /Metadata",
    "/Type /DocTimeStamp",
    "/ByteRange",
    "/Subtype /Widget",
  ]

  /// The catalog keys a later revision may add or change.
  private static let catalogKeys: Set<String> = ["DSS", "AcroForm", "Extensions", "Metadata"]

  /// The interactive form keys a later revision may change.
  private static let formKeys: Set<String> = ["Fields", "SigFlags"]

  /// The order page and structure changes sort before numbered objects.
  private static let objectOrderBase = 2

  /// The page keys a later revision may change.
  private static let pageKeys: Set<String> = ["Annots"]

  /// The order structure changes sort before page changes.
  private static let pageOrder = 1

  /// The field keys a later revision may give a signature field.
  private static let signatureFieldKeys: Set<String> = ["V", "AP", "AS"]

  /// The store's arrays of object references.
  private static let storeArrayKeys: Set<String> = ["Certs", "OCSPs", "CRLs"]

  /// The document security store keys a later revision may grow.
  private static let storeKeys: Set<String> = ["Certs", "OCSPs", "CRLs", "VRI"]

  /// Every change a revision after the signed one made.
  ///
  /// Empty when `signedEnd` is past the document's end or nothing
  /// followed the signed revision.
  internal static func changes(document: Data, signedEnd: Int) -> [SignedContentChange] {
    guard signedEnd > 0, signedEnd < document.count else { return [] }
    let signed = Data(document.prefix(signedEnd))
    guard
      let before = try? PdfDocumentIndex.parse(signed),
      let after = try? PdfDocumentIndex.parse(document)
    else {
      // A view that cannot be indexed cannot be shown to be unchanged.
      return [.documentStructure]
    }
    var changes: Set<SignedContentChange> = []
    let catalogNumber = PdfDocumentIndex.reference(named: "/Root", in: after.trailer)
    if catalogNumber != PdfDocumentIndex.reference(named: "/Root", in: before.trailer) {
      changes.insert(.documentStructure)
    }
    let formNumber = catalogNumber.flatMap { number in
      after.body(of: number, in: document).flatMap { body in
        PdfDocumentIndex.reference(named: "AcroForm", in: body)
      }
    }
    let numbers = Set(after.locations.keys).union(before.locations.keys)
    for number in numbers.sorted() {
      guard
        let body = after.body(of: number, in: document),
        let previous = before.body(of: number, in: signed)
      else {
        changes.formUnion(
          changeOfAbsentObject(
            number,
            absentFromSignedView: before,
            after: after,
            document: document,
            signed: signed
          )
        )
        continue
      }
      guard body != previous else { continue }
      changes.formUnion(
        changeOf(
          number,
          from: previous,
          to: body,
          catalogNumber: catalogNumber,
          formNumber: formNumber
        )
      )
    }
    return changes.sorted { lhs, rhs in order(lhs) < order(rhs) }
  }

  /// A stable order, so a report reads the same way twice.
  private static func order(_ change: SignedContentChange) -> Int {
    switch change {
    case .documentStructure:
      return 0
    case .pageContent:
      return pageOrder
    case .object(let number):
      return objectOrderBase + number
    }
  }

  /// The change an object makes by being on only one side of the
  /// comparison.
  private static func changeOfAbsentObject(
    _ number: Int,
    absentFromSignedView before: PdfDocumentIndex,
    after: PdfDocumentIndex,
    document: Data,
    signed: Data
  ) -> Set<SignedContentChange> {
    let added = after.body(of: number, in: document)
    let removed = before.body(of: number, in: signed)
    guard let added else {
      return removed == nil ? [] : [.object(number)]
    }
    guard removed == nil else { return [] }
    return additionIsAllowed(added) ? [] : [.object(number)]
  }

  /// Whether a revision may add this object.
  ///
  /// Signatures, document timestamps, widgets, appearance streams,
  /// metadata, the store and the data blobs it points at are additions
  /// signing and validation material make. A page, a page tree node, a
  /// font or any other typed object is not.
  private static func additionIsAllowed(_ body: String) -> Bool {
    for marker in allowedAdditionMarkers where body.contains(marker) {
      return true
    }
    guard body.contains("stream") else { return false }
    return !body.contains("/Type")
  }

  /// The change one redefined object makes.
  private static func changeOf(
    _ number: Int,
    from previous: String,
    to body: String,
    catalogNumber: Int?,
    formNumber: Int?
  ) -> Set<SignedContentChange> {
    let differences = differingNames(from: previous, to: body)
    guard differences.isReadable else { return [.object(number)] }
    guard !differences.names.isEmpty else { return [] }
    if number == catalogNumber {
      return differences.names.isSubset(of: catalogKeys) ? [] : [.documentStructure]
    }
    if body.contains("/Type /Page"), !body.contains("/Type /Pages") {
      return differences.names.isSubset(of: pageKeys) ? [] : [.pageContent]
    }
    if body.contains("/Type /Pages") || body.contains("/Type /Catalog") {
      return [.pageContent]
    }
    if number == formNumber {
      return differences.names.isSubset(of: formKeys) ? [] : [.documentStructure]
    }
    if body.contains("/Type /DSS") {
      return growsOnly(from: previous, to: body) ? [] : [.documentStructure]
    }
    if body.contains("/FT /Sig"), differences.names.isSubset(of: signatureFieldKeys) {
      return []
    }
    if body.contains("/Type /Metadata") {
      return []
    }
    if body.contains("/ByteRange") {
      // A signature dictionary does not change after it is taken.
      return [.documentStructure]
    }
    return [.object(number)]
  }

  /// The entry names whose value differs between two dictionaries.
  private static func differingNames(from previous: String, to body: String) -> EntryDifferences {
    guard
      let before = try? PdfValidationStore.DictionarySyntax(previous),
      let after = try? PdfValidationStore.DictionarySyntax(body)
    else {
      return EntryDifferences(names: [], isReadable: false)
    }
    let names = Set(before.entries.map(\.name)).union(after.entries.map(\.name))
    let differing = names.filter { name in
      before.entry(named: name).map { before.value(of: $0) }
        != after.entry(named: name).map { after.value(of: $0) }
    }
    return EntryDifferences(names: differing, isReadable: true)
  }

  /// Whether a store change only adds material.
  ///
  /// A store that loses a certificate, an answer or a CRL loses the
  /// evidence a validator needs, so a revision may grow it but never
  /// shrink or rewrite it.
  private static func growsOnly(from previous: String, to body: String) -> Bool {
    let differences = differingNames(from: previous, to: body)
    guard differences.isReadable, differences.names.isSubset(of: storeKeys) else { return false }
    guard
      let before = try? PdfValidationStore.DictionarySyntax(previous),
      let after = try? PdfValidationStore.DictionarySyntax(body)
    else {
      return false
    }
    for key in storeArrayKeys where differences.names.contains(key) {
      guard
        let previousEntry = before.entry(named: key),
        let entry = after.entry(named: key),
        Set(references(in: before.value(of: previousEntry)))
          .isSubset(of: Set(references(in: after.value(of: entry))))
      else {
        return false
      }
    }
    if differences.names.contains("VRI") {
      guard
        let previousEntry = before.entry(named: "VRI"),
        let entry = after.entry(named: "VRI"),
        let previousList = try? PdfValidationStore.DictionarySyntax(
          before.value(of: previousEntry)),
        let list = try? PdfValidationStore.DictionarySyntax(after.value(of: entry)),
        Set(previousList.entries.map(\.name)).isSubset(of: Set(list.entries.map(\.name)))
      else {
        return false
      }
    }
    return true
  }

  /// The `N G R` references an array value carries, as written.
  private static func references(in value: String) -> [String] {
    let tokens = value.split(whereSeparator: \.isWhitespace)
    var found: [String] = []
    var index = tokens.startIndex
    while index < tokens.endIndex {
      let number = tokens[index]
      let generation = tokens.index(after: index)
      let marker = generation < tokens.endIndex ? tokens.index(after: generation) : generation
      guard
        number.allSatisfy(\.isNumber),
        generation < tokens.endIndex,
        tokens[generation].allSatisfy(\.isNumber),
        marker < tokens.endIndex,
        tokens[marker] == "R"
      else {
        index = generation
        continue
      }
      found.append("\(number) \(tokens[generation])")
      index = tokens.index(after: marker)
    }
    return found
  }
}
