// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Per-object revision comparison dispatch for `PdfSignedContentAnalysis`.
extension PdfSignedContentAnalysis {
  /// Types no revision may give an object it did not already have.
  private static let fixedTypes: Set<String> = ["/XRef", "/ObjStm", "/Metadata"]

  /// Dictionary keys a redefined `/Metadata` stream may change.
  private static let metadataStreamKeys: Set<String> = [
    "Length", "Filter", "DecodeParms",
  ]

  /// Types that decide how a page tree reads.
  private static let treeTypes: Set<String> = ["/Pages", "/Catalog"]

  /// Entry names whose raw value differs between two leading dictionaries.
  internal static func differingNames(
    from previous: String,
    to body: String
  ) -> EntryDifferences {
    guard
      let before = PdfTypeEntry.dictionarySyntax(of: previous),
      let after = PdfTypeEntry.dictionarySyntax(of: body)
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

  /// Compares every object present in `signed.locations`.
  internal static func existingObjectChanges(
    in context: Context,
    state: inout VerificationState
  ) -> Set<SignedContentChange> {
    var found: Set<SignedContentChange> = []
    if Self.hasIncompatibleTrailer(in: context) {
      found.insert(.documentStructure)
    }
    for number in context.signed.locations.keys.sorted() {
      guard
        let older = context.signed.locations[number],
        let newer = context.newest.locations[number],
        newer.generation == older.generation,
        let previous = context.signedBody(of: number),
        let body = context.body(of: number)
      else {
        found.insert(.object(number))
        continue
      }
      guard body != previous else { continue }
      found.formUnion(
        Self.changeOf(
          number, previous: previous, body: body, context: context, state: &state
        )
      )
    }
    return found
  }

  /// Whether trailer `/Root` or `/Info` changed across revisions.
  private static func hasIncompatibleTrailer(in context: Context) -> Bool {
    guard
      context.catalogNumber != nil,
      PdfDocumentIndex.fullReference(
        named: "/Root", in: context.newest.trailer
      )
        == PdfDocumentIndex.fullReference(
          named: "/Root", in: context.signed.trailer
        )
    else {
      return true
    }
    let newestInfo = Self.trailerEntryValue(
      named: "Info", in: context.newest.trailer
    )
    let signedInfo = Self.trailerEntryValue(
      named: "Info", in: context.signed.trailer
    )
    return newestInfo != signedInfo
  }

  /// Extracts a raw top-level value from a trailer dictionary when present.
  private static func trailerEntryValue(
    named key: String,
    in trailer: String
  ) -> String? {
    guard
      let syntax = try? PdfValidationStore.DictionarySyntax.loose(trailer),
      let entry = syntax.entry(named: key)
    else {
      return nil
    }
    return syntax.value(of: entry)
  }

  /// The change one redefined object makes.
  private static func changeOf(
    _ number: Int,
    previous: String,
    body: String,
    context: Context,
    state: inout VerificationState
  ) -> Set<SignedContentChange> {
    if let pageNumbers = context.signedIndirectPageAnnots[number],
      !pageNumbers.isEmpty
    {
      return Self.indirectAnnotsVerdict(
        previous: previous,
        body: body,
        pageNumbers: pageNumbers,
        context: context,
        state: &state
      )
    }
    if number == context.signedIndirectFieldsNumber {
      return Self.indirectFieldsVerdict(
        previous: previous, body: body, context: context, state: &state
      )
    }
    let differences = Self.differingNames(from: previous, to: body)
    guard differences.isReadable else { return [.object(number)] }
    if differences.names.isEmpty,
      !PdfTypeEntry.hasStream(previous),
      !PdfTypeEntry.hasStream(body)
    {
      return []
    }
    let comparison = ObjectComparison(
      number: number,
      previous: previous,
      body: body,
      differences: differences
    )
    switch Self.namedVerdict(comparison, context: context, state: &state) {
    case .changes(let verdict):
      return verdict
    case .unnamed:
      return Self.redefinedVerdict(comparison, context: context, state: &state)
    }
  }

  /// Verdict for structural objects named by role or `/Type`.
  private static func namedVerdict(
    _ comparison: ObjectComparison,
    context: Context,
    state: inout VerificationState
  ) -> Verdict {
    let type = PdfTypeEntry.value(of: "Type", in: comparison.body)
    if comparison.number == context.catalogNumber {
      return .changes(
        Self.catalogVerdict(comparison, context: context, state: &state)
      )
    }
    if type == "/Page"
      || PdfTypeEntry.value(of: "Type", in: comparison.previous) == "/Page"
    {
      return .changes(
        Self.pageVerdict(comparison, context: context, state: &state)
      )
    }
    if let type, Self.treeTypes.contains(type) {
      return .changes([.pageContent])
    }
    if comparison.number == context.signedFormNumber {
      return .changes(
        Self.formVerdict(comparison, context: context, state: &state)
      )
    }
    guard type == "/DSS" else { return .unnamed }
    guard PdfTypeEntry.value(of: "Type", in: comparison.previous) == "/DSS"
    else {
      return .changes([.documentStructure])
    }
    return .changes(
      PdfValidationStoreGrowth.growsOnly(
        from: comparison.previous, to: comparison.body
      ) ? [] : [.documentStructure]
    )
  }

  /// Verdict for an object no structural role names directly.
  private static func redefinedVerdict(
    _ comparison: ObjectComparison,
    context: Context,
    state: inout VerificationState
  ) -> Set<SignedContentChange> {
    if let type = PdfTypeEntry.value(of: "Type", in: comparison.body),
      Self.fixedTypes.contains(type)
    {
      guard
        PdfTypeEntry.value(of: "Type", in: comparison.previous) == type,
        PdfTypeEntry.hasStream(comparison.previous),
        PdfTypeEntry.hasStream(comparison.body)
      else {
        return [.object(comparison.number)]
      }
      if type == "/Metadata" {
        guard
          !context.hasNoChangesDocMdp,
          comparison.differences.names.isSubset(of: Self.metadataStreamKeys),
          let syntax = PdfTypeEntry.dictionarySyntax(of: comparison.body),
          PdfPageAnnotationGrowth.containsNoForbiddenKeys(syntax)
        else {
          return [.object(comparison.number)]
        }
      }
      return []
    }
    if case .changes(let verdict) =
      Self.signatureFieldOrWidgetRedefinitionVerdict(
        comparison, context: context, state: &state
      )
    {
      return verdict
    }
    if PdfTypeEntry.value(of: "ByteRange", in: comparison.body) != nil {
      return [.documentStructure]
    }
    return [.object(comparison.number)]
  }
}
