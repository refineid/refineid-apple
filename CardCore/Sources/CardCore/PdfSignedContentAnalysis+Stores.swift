// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Document security store reachability and indirect container
/// resolution for `PdfSignedContentAnalysis`.
extension PdfSignedContentAnalysis {
  /// Evidence array keys in `/DSS` and `/VRI` entries.
  private static let dssCategoryKeys = ["Certs", "OCSPs", "CRLs"]

  /// Stream-reference keys inside one `/VRI` signature entry.
  private static let vriStreamKeys = ["Cert", "OCSP", "CRL", "TS"]

  /// Maps indirect `/Annots` array object numbers in `index` to their
  /// owning `/Page` object numbers.
  internal static func indirectPageAnnots(
    in index: PdfDocumentIndex,
    document: Data
  ) -> [Int: [Int]] {
    var mapping: [Int: [Int]] = [:]
    for pageNumber in index.locations.keys.sorted() {
      guard
        let body = index.comparisonBody(of: pageNumber, in: document),
        PdfTypeEntry.value(of: "Type", in: body) == "/Page",
        let annotsNumber = index.verifiedReference(named: "Annots", in: body)
      else {
        continue
      }
      mapping[annotsNumber, default: []].append(pageNumber)
    }
    return mapping
  }

  /// Collects `storeNumber` and every newly added indirect array, `/VRI`
  /// dictionary, and untyped evidence stream referenced by `/DSS`.
  internal static func dssAuthorizedObjects(
    storeNumber: Int,
    in context: Context
  ) -> Set<Int> {
    guard
      let storeBody = context.body(of: storeNumber),
      !PdfTypeEntry.hasStream(storeBody),
      PdfTypeEntry.value(of: "Type", in: storeBody) == "/DSS",
      let syntax = PdfTypeEntry.dictionarySyntax(of: storeBody)
    else {
      return []
    }
    var allowed: Set<Int> = [storeNumber]
    for key in Self.dssCategoryKeys where syntax.entry(named: key) != nil {
      allowed.formUnion(
        Self.authorizedEvidenceCategory(
          named: key, in: storeBody, context: context
        )
      )
    }
    if syntax.entry(named: "VRI") != nil,
      let vri = Self.resolvedDictionaryWithContainer(
        named: "VRI", in: storeBody, context: context
      ),
      let vriSyntax = PdfTypeEntry.dictionarySyntax(of: vri.text)
    {
      allowed.formUnion(vri.addedContainers)
      for entry in vriSyntax.entries {
        allowed.formUnion(
          Self.authorizedVriEntry(
            named: entry.name, in: vri.text, context: context
          )
        )
      }
    }
    return allowed
  }

  /// Resolves a direct or indirect dictionary entry in `body`.
  internal static func resolvedDictionaryText(
    named name: String,
    in body: String,
    index: PdfDocumentIndex,
    document: Data
  ) -> String? {
    guard
      let syntax = PdfTypeEntry.dictionarySyntax(of: body),
      let entry = syntax.entry(named: name)
    else {
      return nil
    }
    let raw = syntax.value(of: entry)
    if (try? PdfValidationStore.DictionarySyntax(raw)) != nil {
      return raw
    }
    guard
      let reference = try? PdfValidationStore.ValueParser.reference(in: raw),
      index.locations[reference.number]?.generation == reference.generation,
      let resolved = index.comparisonBody(of: reference.number, in: document),
      !PdfTypeEntry.hasStream(resolved),
      (try? PdfValidationStore.DictionarySyntax(resolved)) != nil
    else {
      return nil
    }
    return resolved
  }

  /// Resolves a direct or indirect dictionary in `newest`, recording any
  /// newly added indirect container.
  internal static func resolvedDictionaryWithContainer(
    named name: String,
    in body: String,
    context: Context
  ) -> (text: String, addedContainers: Set<Int>)? {
    guard
      let syntax = PdfTypeEntry.dictionarySyntax(of: body),
      let entry = syntax.entry(named: name)
    else {
      return nil
    }
    let raw = syntax.value(of: entry)
    if (try? PdfValidationStore.DictionarySyntax(raw)) != nil {
      return (raw, [])
    }
    guard
      let reference = try? PdfValidationStore.ValueParser.reference(in: raw),
      reference.generation == 0,
      context.newest.locations[reference.number]?.generation == 0,
      let resolved = context.body(of: reference.number),
      !PdfTypeEntry.hasStream(resolved),
      (try? PdfValidationStore.DictionarySyntax(resolved)) != nil
    else {
      return nil
    }
    let containers: Set<Int> =
      context.signed.locations[reference.number] == nil
      ? [reference.number] : []
    return (resolved, containers)
  }

  /// Resolves an optional reference-array entry in `body` (empty string
  /// when absent).
  internal static func resolvedArrayText(
    named name: String,
    in body: String,
    index: PdfDocumentIndex,
    document: Data
  ) -> String? {
    guard
      let syntax = PdfTypeEntry.dictionarySyntax(of: body),
      let entry = syntax.entry(named: name)
    else {
      return ""
    }
    let raw = syntax.value(of: entry)
    if PdfObjectReferences.strictReferences(in: raw).isValid {
      return raw
    }
    guard
      let reference = try? PdfValidationStore.ValueParser.reference(in: raw),
      index.locations[reference.number]?.generation == reference.generation,
      let resolved = index.comparisonBody(of: reference.number, in: document),
      PdfObjectReferences.strictReferences(in: resolved).isValid
    else {
      return nil
    }
    return resolved
  }

  /// Resolves an optional reference-array entry in `newest`, recording
  /// any newly added indirect array object.
  internal static func resolvedArrayWithContainer(
    named name: String,
    in body: String,
    context: Context
  ) -> (text: String, addedContainers: Set<Int>)? {
    guard
      let syntax = PdfTypeEntry.dictionarySyntax(of: body),
      let entry = syntax.entry(named: name)
    else {
      return ("", [])
    }
    let raw = syntax.value(of: entry)
    if PdfObjectReferences.strictReferences(in: raw).isValid {
      return (raw, [])
    }
    guard
      let reference = try? PdfValidationStore.ValueParser.reference(in: raw),
      reference.generation == 0,
      context.newest.locations[reference.number]?.generation == 0,
      let resolved = context.body(of: reference.number),
      PdfObjectReferences.strictReferences(in: resolved).isValid
    else {
      return nil
    }
    let containers: Set<Int> =
      context.signed.locations[reference.number] == nil
      ? [reference.number] : []
    return (resolved, containers)
  }

  /// Collects newly added untyped stream objects in one DSS/VRI category.
  private static func authorizedEvidenceCategory(
    named name: String,
    in dictionaryBody: String,
    context: Context
  ) -> Set<Int> {
    guard
      let resolved = Self.resolvedArrayWithContainer(
        named: name, in: dictionaryBody, context: context
      )
    else {
      return []
    }
    let parsed = PdfObjectReferences.strictReferences(in: resolved.text)
    guard parsed.isValid else { return [] }
    var allowed = resolved.addedContainers
    for reference in parsed.references
    where reference.generation == 0
      && context.newest.locations[reference.number]?.generation == 0
      && context.signed.locations[reference.number] == nil
    {
      if Self.isUntypedEvidenceStream(reference.number, in: context) {
        allowed.insert(reference.number)
      }
    }
    return allowed
  }

  /// Collects newly added objects inside one `/VRI` entry dictionary.
  private static func authorizedVriEntry(
    named name: String,
    in vriBody: String,
    context: Context
  ) -> Set<Int> {
    guard
      let entry = Self.resolvedDictionaryWithContainer(
        named: name, in: vriBody, context: context
      ),
      let syntax = PdfTypeEntry.dictionarySyntax(of: entry.text)
    else {
      return []
    }
    var allowed = entry.addedContainers
    for key in Self.vriStreamKeys where syntax.entry(named: key) != nil {
      if let streamRef = PdfDocumentIndex.fullReference(
        named: key, in: entry.text
      ),
        streamRef.generation == 0,
        context.newest.locations[streamRef.number]?.generation == 0,
        context.signed.locations[streamRef.number] == nil,
        Self.isUntypedEvidenceStream(streamRef.number, in: context)
      {
        allowed.insert(streamRef.number)
      } else {
        allowed.formUnion(
          Self.authorizedEvidenceCategory(
            named: key, in: entry.text, context: context
          )
        )
      }
    }
    return allowed
  }

  /// Whether `number` is a raw untyped data stream carrying no forbidden
  /// action keys.
  private static func isUntypedEvidenceStream(
    _ number: Int,
    in context: Context
  ) -> Bool {
    guard
      let body = context.body(of: number),
      PdfTypeEntry.hasStream(body),
      PdfTypeEntry.value(of: "Type", in: body) == nil,
      PdfTypeEntry.value(of: "Subtype", in: body) == nil,
      let syntax = PdfTypeEntry.dictionarySyntax(of: body)
    else {
      return false
    }
    return PdfPageAnnotationGrowth.containsNoForbiddenKeys(syntax)
  }
}
