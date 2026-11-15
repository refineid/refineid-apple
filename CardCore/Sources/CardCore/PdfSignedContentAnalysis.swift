// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What the revisions after a signed one change in a PDF.
///
/// The signed revision is indexed on its own and compared with the
/// newest view of the document, object by object, number by number. An
/// object whose body is the same in both views, at the same generation,
/// is untouched. A later revision may, without changing what the signer
/// saw, add a document security store, certificates, OCSP responses and
/// CRLs for it, a signature or document timestamp and the widgets they
/// need, metadata, and cross-reference or object streams; it may give
/// the catalog `/DSS`, `/AcroForm` or `/Metadata`, append signed
/// signature fields to the form, and append their widgets to a page.
///
/// Every other change is reported. A document that cannot be indexed is
/// reported as changed rather than trusted.
internal enum PdfSignedContentAnalysis {
  /// What one object comparison needs besides the two bodies.
  private struct Context {
    /// The newest catalog's object number.
    let catalogNumber: Int?

    /// The newest interactive form's object number.
    let formNumber: Int?

    /// The newest view of the document.
    let newest: PdfDocumentIndex

    /// The document itself, for reading an object's body.
    let document: Data
  }

  /// What the rules say about one rewritten object.
  private enum Verdict {
    /// The changes the object makes.
    case changes(Set<SignedContentChange>)

    /// No rule names the object, so what it is decides.
    case unnamed
  }

  /// The entry names that differ between two dictionaries, and whether
  /// both could be read at all.
  private struct EntryDifferences {
    /// The names whose value is not the same in both.
    let names: Set<String>

    /// Whether both dictionaries could be parsed.
    let isReadable: Bool
  }

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

  /// The types an object added after signing may have.
  private static let addedTypes: Set<String> = [
    "/XRef", "/ObjStm", "/DSS", "/Metadata", "/DocTimeStamp",
  ]

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
    let catalogNumber = PdfDocumentIndex.reference(named: "/Root", in: after.trailer)
    let context = Context(
      catalogNumber: catalogNumber,
      formNumber: catalogNumber.flatMap { number in
        after.comparisonBody(of: number, in: document).flatMap { body in
          PdfDocumentIndex.reference(named: "AcroForm", in: body)
        }
      },
      newest: after,
      document: document
    )
    var changes: Set<SignedContentChange> = []
    if catalogNumber != PdfDocumentIndex.reference(named: "/Root", in: before.trailer) {
      changes.insert(.documentStructure)
    }
    let numbers = Set(after.locations.keys).union(before.locations.keys)
    for number in numbers.sorted() {
      guard let newer = after.locations[number], let older = before.locations[number] else {
        changes.formUnion(
          changeOfAbsentObject(
            number, absentFromSignedView: before, after: after, document: document, signed: signed
          )
        )
        continue
      }
      // A reused number at a higher generation frees what the signed
      // revision's references named, whatever the new body says.
      guard newer.generation == older.generation else {
        changes.insert(.object(number))
        continue
      }
      guard
        let body = after.comparisonBody(of: number, in: document),
        let previous = before.comparisonBody(of: number, in: signed)
      else {
        changes.insert(.object(number))
        continue
      }
      guard body != previous else { continue }
      changes.formUnion(changeOf(number, previous: previous, body: body, context: context))
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
    guard let added = after.comparisonBody(of: number, in: document) else {
      return before.comparisonBody(of: number, in: signed) == nil ? [] : [.object(number)]
    }
    guard before.comparisonBody(of: number, in: signed) == nil else { return [] }
    return additionIsAllowed(added) ? [] : [.object(number)]
  }

  /// Whether a revision may add this object.
  ///
  /// Signatures, document timestamps, widgets, appearance streams,
  /// metadata, the store and the data blobs it points at are additions
  /// signing and validation material make. A page, a page tree node, a
  /// font or any other typed object is not.
  private static func additionIsAllowed(_ body: String) -> Bool {
    if let type = PdfTypeEntry.value(of: "Type", in: body), addedTypes.contains(type) {
      return true
    }
    if PdfTypeEntry.value(of: "Subtype", in: body) == "/Widget" { return true }
    if PdfTypeEntry.value(of: "FT", in: body) == "/Sig" { return true }
    if PdfTypeEntry.value(of: "ByteRange", in: body) != nil { return true }
    // An appearance or data stream: bytes no dictionary types.
    return body.contains("stream") && PdfTypeEntry.value(of: "Type", in: body) == nil
  }

  /// The change one redefined object makes.
  private static func changeOf(
    _ number: Int,
    previous: String,
    body: String,
    context: Context
  ) -> Set<SignedContentChange> {
    let differences = differingNames(from: previous, to: body)
    guard differences.isReadable else { return [.object(number)] }
    guard !differences.names.isEmpty else { return [] }
    switch namedVerdict(number, previous, body, differences, context) {
    case .changes(let verdict):
      return verdict
    case .unnamed:
      return redefinedVerdict(number, previous: previous, body: body, differences)
    }
  }

  /// The verdict for an object the revision rules name by kind, or
  /// unnamed when no rule knows it.
  private static func namedVerdict(
    _ number: Int,
    _ previous: String,
    _ body: String,
    _ differences: EntryDifferences,
    _ context: Context
  ) -> Verdict {
    if number == context.catalogNumber {
      return .changes(differences.names.isSubset(of: catalogKeys) ? [] : [.documentStructure])
    }
    if PdfTypeEntry.value(of: "Type", in: body) == "/Page" {
      return .changes(pageVerdict(previous, body, differences, context))
    }
    if let type = PdfTypeEntry.value(of: "Type", in: body), type == "/Pages" || type == "/Catalog" {
      return .changes([.pageContent])
    }
    if number == context.formNumber {
      return .changes(formVerdict(previous, body, differences, context))
    }
    guard PdfTypeEntry.value(of: "Type", in: body) == "/DSS" else { return .unnamed }
    return .changes(
      PdfValidationStoreGrowth.growsOnly(from: previous, to: body)
        ? [] : [.documentStructure])
  }

  /// The verdict for a rewritten page, which may gain signed signature
  /// widgets and nothing else.
  private static func pageVerdict(
    _ previous: String,
    _ body: String,
    _ differences: EntryDifferences,
    _ context: Context
  ) -> Set<SignedContentChange> {
    guard differences.names.isSubset(of: pageKeys) else { return [.pageContent] }
    guard differences.names.contains("Annots") else { return [] }
    guard
      PdfPageAnnotationGrowth.annotationsGrowOnly(
        from: previous, to: body, newest: context.newest, document: context.document)
    else {
      return [.pageContent]
    }
    return []
  }

  /// The verdict for a rewritten interactive form, which may only gain
  /// signed signature fields.
  private static func formVerdict(
    _ previous: String,
    _ body: String,
    _ differences: EntryDifferences,
    _ context: Context
  ) -> Set<SignedContentChange> {
    guard differences.names.isSubset(of: formKeys) else { return [.documentStructure] }
    guard differences.names.contains("Fields") else { return [] }
    guard formFieldsGrowOnly(from: previous, to: body, context: context) else {
      return [.documentStructure]
    }
    return []
  }

  /// Whether a form's fields still name every node they named and only
  /// add signature fields.
  private static func formFieldsGrowOnly(
    from previous: String,
    to body: String,
    context: Context
  ) -> Bool {
    let kept = PdfObjectReferences.references(
      in: PdfTypeEntry.value(of: "Fields", in: previous) ?? "")
    let grown = PdfObjectReferences.references(in: PdfTypeEntry.value(of: "Fields", in: body) ?? "")
    guard Array(grown.prefix(kept.count)) == kept else { return false }
    return grown.dropFirst(kept.count).allSatisfy { reference in
      guard
        let number = Int(reference.split(separator: " ").first ?? ""),
        let field = context.newest.comparisonBody(of: number, in: context.document)
      else {
        return false
      }
      return PdfTypeEntry.value(of: "FT", in: field) == "/Sig"
    }
  }

  /// The verdict for an object no rule names by kind.
  private static func redefinedVerdict(
    _ number: Int,
    previous: String,
    body: String,
    _ differences: EntryDifferences
  ) -> Set<SignedContentChange> {
    switch PdfTypeEntry.value(of: "Type", in: body) {
    case "/ObjStm", "/XRef":
      // The objects they carry are compared on their own, by number.
      return []
    case "/Metadata":
      return []
    default:
      break
    }
    if PdfTypeEntry.value(of: "FT", in: body) == "/Sig",
      differences.names.isSubset(of: signatureFieldKeys)
    {
      // A field may be filled once: one that carried a value may not be
      // refilled under a signature.
      guard differences.names.contains("V") else { return [] }
      return PdfTypeEntry.value(of: "V", in: previous) == nil ? [] : [.documentStructure]
    }
    if PdfTypeEntry.value(of: "ByteRange", in: body) != nil {
      // A signature dictionary does not change after it is taken.
      return [.documentStructure]
    }
    return [.object(number)]
  }

  /// The entry names whose value differs between two dictionaries.
  private static func differingNames(from previous: String, to body: String) -> EntryDifferences {
    guard
      let before = try? PdfValidationStore.DictionarySyntax(
        PdfTypeEntry.dictionary(of: previous)),
      let after = try? PdfValidationStore.DictionarySyntax(PdfTypeEntry.dictionary(of: body))
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
}
