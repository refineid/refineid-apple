// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Context assembly, catalog helper rules, and scoped addition
/// authorization for `PdfSignedContentAnalysis`.
extension PdfSignedContentAnalysis {
  /// Structural `/Type` values always permitted for new objects.
  private static let structuralAddedTypes: Set<String> = ["/XRef", "/ObjStm"]

  /// Parses `signed` and `newest` indexes and builds `Context`, or nil
  /// when either view cannot be indexed.
  internal static func makeContext(
    document: Data,
    signedEnd: Int,
    candidates: [PostSignatureCandidate]
  ) -> Context? {
    let signedDocument = Data(document.prefix(signedEnd))
    guard
      let signed = try? PdfDocumentIndex.parse(signedDocument),
      let newest = try? PdfDocumentIndex.parse(document)
    else {
      return nil
    }
    let newestRefs = Self.catalogAndForm(in: newest, document: document)
    let signedRefs = Self.catalogAndForm(in: signed, document: signedDocument)
    let hasNoChanges = Self.hasNoChangesDocMdp(
      in: signed, document: signedDocument
    )
    return Context(
      newest: newest,
      document: document,
      signed: signed,
      signedDocument: signedDocument,
      catalogNumber: newestRefs.catalog,
      signedFormNumber: signedRefs.form,
      formNumber: newestRefs.form,
      signedIndirectFieldsNumber: Self.nestedReference(
        outer: signedRefs.form,
        named: "Fields",
        in: signed,
        document: signedDocument
      ),
      signedIndirectPageAnnots: Self.indirectPageAnnots(
        in: signed, document: signedDocument
      ),
      hasNoChangesDocMdp: hasNoChanges,
      postSignatures: Self.eligiblePostSignatures(
        from: candidates,
        signedEnd: signedEnd,
        signed: signed,
        newest: newest,
        hasNoChanges: hasNoChanges
      )
    )
  }

  /// Seeds `allowedAddedObjects` with structural `/XRef` and `/ObjStm`
  /// streams, eligible post-signatures, and `/DSS` evidence objects.
  internal static func initialAllowedAddedObjects(
    in context: Context
  ) -> Set<Int> {
    var allowed = Set(context.postSignatures.keys)
    for number in context.newest.locations.keys
    where context.signed.locations[number] == nil {
      guard let body = context.body(of: number) else { continue }
      let type = PdfTypeEntry.value(of: "Type", in: body)
      if let type, Self.structuralAddedTypes.contains(type) {
        allowed.insert(number)
      } else if type == "/Metadata", !context.hasNoChangesDocMdp {
        allowed.insert(number)
      } else if type == "/DSS" {
        allowed.formUnion(
          Self.dssAuthorizedObjects(storeNumber: number, in: context)
        )
      }
    }
    return allowed
  }

  /// Merges 1-to-1 widget and field signature bindings into `state`.
  internal static func mergeBindings(
    widgets: [Int: Int],
    fields: [Int: Int],
    allowed: Set<Int>,
    into state: inout VerificationState
  ) -> Bool {
    for signature in widgets.keys where state.widgetBySignature[signature] != nil {
      return false
    }
    for (signature, field) in fields {
      if let existing = state.fieldBySignature[signature], existing != field {
        return false
      }
    }
    for (signature, widget) in widgets {
      state.widgetBySignature[signature] = widget
    }
    for (signature, field) in fields {
      state.fieldBySignature[signature] = field
    }
    state.allowedAddedObjects.formUnion(allowed)
    return true
  }

  /// Validates that catalog `/DSS` preserves all entries of any store in
  /// `previous`.
  internal static func catalogDssGrowsOnly(
    from previous: String,
    to body: String,
    context: Context
  ) -> Bool {
    guard
      let afterStore = Self.resolvedDictionaryText(
        named: "DSS",
        in: body,
        index: context.newest,
        document: context.document
      ),
      PdfTypeEntry.value(of: "Type", in: afterStore) == "/DSS"
    else {
      return false
    }
    guard
      let beforeSyntax = PdfTypeEntry.dictionarySyntax(of: previous),
      beforeSyntax.entry(named: "DSS") != nil
    else {
      return true
    }
    guard
      let beforeStore = Self.resolvedDictionaryText(
        named: "DSS",
        in: previous,
        index: context.signed,
        document: context.signedDocument
      )
    else {
      return false
    }
    return PdfValidationStoreGrowth.growsOnly(from: beforeStore, to: afterStore)
  }

  /// Validates adding or growing `/AcroForm` on the catalog.
  internal static func catalogAcroFormGrowsOnly(
    from previous: String,
    to body: String,
    context: Context,
    state: inout VerificationState
  ) -> Bool {
    guard
      let afterForm = Self.resolvedDictionaryWithContainer(
        named: "AcroForm", in: body, context: context
      )
    else {
      return false
    }
    if let beforeSyntax = PdfTypeEntry.dictionarySyntax(of: previous),
      beforeSyntax.entry(named: "AcroForm") != nil
    {
      return Self.existingCatalogFormGrowsOnly(
        from: previous,
        afterForm: afterForm,
        context: context,
        state: &state
      )
    }
    guard
      let syntax = PdfTypeEntry.dictionarySyntax(of: afterForm.text),
      Set(syntax.entries.map(\.name)).isSubset(of: ["Fields", "SigFlags"]),
      let grownFields = Self.resolvedArrayWithContainer(
        named: "Fields", in: afterForm.text, context: context
      )
    else {
      return false
    }
    return Self.fieldsArrayGrowsOnly(
      from: "",
      to: grownFields.text,
      addedContainers: afterForm.addedContainers.union(
        grownFields.addedContainers
      ),
      context: context,
      state: &state
    )
  }

  /// Validates a newly added or updated catalog `/Metadata` reference.
  internal static func catalogMetadataIsValid(
    in body: String,
    context: Context,
    state: inout VerificationState
  ) -> Bool {
    guard
      !context.hasNoChangesDocMdp,
      let metadataRef = PdfDocumentIndex.fullReference(
        named: "Metadata", in: body
      ),
      let metadataNumber = context.newest.verifiedReference(
        named: "Metadata", in: body
      ),
      let metadataBody = context.body(of: metadataNumber),
      PdfTypeEntry.hasStream(metadataBody),
      PdfTypeEntry.value(of: "Type", in: metadataBody) == "/Metadata"
    else {
      return false
    }
    if context.signed.locations[metadataNumber] == nil {
      guard metadataRef.generation == 0 else { return false }
      state.allowedAddedObjects.insert(metadataNumber)
    }
    return true
  }

  /// Validates that an `AcroForm` `/Fields` array keeps existing entries
  /// in order and appends only valid post-signature `/FT /Sig` fields.
  internal static func fieldsArrayGrowsOnly(
    from keptValue: String,
    to grownValue: String,
    addedContainers: Set<Int>,
    context: Context,
    state: inout VerificationState
  ) -> Bool {
    let kept = PdfObjectReferences.strictReferences(in: keptValue)
    let grown = PdfObjectReferences.strictReferences(in: grownValue)
    guard
      kept.isValid,
      grown.isValid,
      Array(grown.references.prefix(kept.references.count)) == kept.references
    else {
      return false
    }
    var fields: [Int: Int] = [:]
    var allowed = addedContainers
    for reference in grown.references.dropFirst(kept.references.count) {
      guard
        reference.generation == 0,
        context.newest.locations[reference.number]?.generation == 0,
        context.signed.locations[reference.number] == nil,
        let approved = Self.approveAddedFormField(
          number: reference.number, context: context, state: state
        ),
        fields[approved.signatureNumber] == nil
      else {
        return false
      }
      fields[approved.signatureNumber] = reference.number
      allowed.formUnion(approved.allowedObjects)
    }
    return Self.mergeBindings(
      widgets: [:], fields: fields, allowed: allowed, into: &state
    )
  }

  /// Validates one newly added `/FT /Sig` entry in `AcroForm /Fields`.
  private static func approveAddedFormField(
    number: Int,
    context: Context,
    state: VerificationState
  ) -> (signatureNumber: Int, allowedObjects: Set<Int>)? {
    guard
      let field = context.body(of: number),
      !PdfTypeEntry.hasStream(field),
      let syntax = PdfTypeEntry.dictionarySyntax(of: field),
      PdfPageAnnotationGrowth.containsNoForbiddenKeys(syntax),
      PdfTypeEntry.value(of: "FT", in: field) == "/Sig",
      let sigRef = PdfDocumentIndex.fullReference(named: "V", in: field),
      sigRef.generation == 0,
      let signatureNumber = context.newest.verifiedReference(
        named: "V", in: field
      ),
      let candidate = context.postSignatures[signatureNumber]
    else {
      return nil
    }
    var allowed: Set<Int> = [number]
    if PdfTypeEntry.value(of: "Subtype", in: field) != "/Widget"
      || state.widgetBySignature[signatureNumber] == nil
    {
      if syntax.entry(named: "AP") != nil || syntax.entry(named: "AS") != nil {
        guard !candidate.isTimestamp, candidate.isCryptographicallyVerified
        else {
          return nil
        }
        if let apEntry = syntax.entry(named: "AP") {
          let approval = PdfPageAnnotationGrowth.approvedAppearanceSubgraph(
            apValue: syntax.value(of: apEntry),
            newest: context.newest,
            document: context.document,
            signed: context.signed
          )
          guard approval.isAllowed else { return nil }
          allowed.formUnion(approval.allowedObjects)
        }
      }
    }
    return (signatureNumber, allowed)
  }

  /// Resolves the trailer `/Root` catalog number and its `/AcroForm` number.
  private static func catalogAndForm(
    in index: PdfDocumentIndex,
    document: Data
  ) -> (catalog: Int?, form: Int?) {
    let catalog = index.verifiedReference(named: "/Root", in: index.trailer)
    let form = Self.nestedReference(
      outer: catalog, named: "AcroForm", in: index, document: document
    )
    return (catalog, form)
  }

  /// Resolves an indirect reference `named` inside the object `outer`.
  private static func nestedReference(
    outer: Int?,
    named: String,
    in index: PdfDocumentIndex,
    document: Data
  ) -> Int? {
    outer.flatMap { number in
      index.comparisonBody(of: number, in: document).flatMap { body in
        index.verifiedReference(named: named, in: body)
      }
    }
  }

  /// Filters `candidates` to signatures added after `signedEnd` that remain
  /// live in `newest` and satisfy `hasNoChanges`.
  private static func eligiblePostSignatures(
    from candidates: [PostSignatureCandidate],
    signedEnd: Int,
    signed: PdfDocumentIndex,
    newest: PdfDocumentIndex,
    hasNoChanges: Bool
  ) -> [Int: PostSignatureCandidate] {
    var eligible: [Int: PostSignatureCandidate] = [:]
    for candidate in candidates
    where candidate.revisionEnd > signedEnd
      && signed.locations[candidate.objectNumber] == nil
      && newest.locations[candidate.objectNumber] == candidate.location
      && (!hasNoChanges || candidate.isTimestamp)
    {
      eligible[candidate.objectNumber] = candidate
    }
    return eligible
  }

  /// Validates that an existing catalog `/AcroForm` entry only grows.
  private static func existingCatalogFormGrowsOnly(
    from previous: String,
    afterForm: (text: String, addedContainers: Set<Int>),
    context: Context,
    state: inout VerificationState
  ) -> Bool {
    guard
      let beforeForm = Self.resolvedDictionaryText(
        named: "AcroForm",
        in: previous,
        index: context.signed,
        document: context.signedDocument
      )
    else {
      return false
    }
    let diff = Self.differingNames(from: beforeForm, to: afterForm.text)
    guard diff.isReadable else { return false }
    let comparison = ObjectComparison(
      number: context.catalogNumber ?? 0,
      previous: beforeForm,
      body: afterForm.text,
      differences: diff
    )
    let verdict = Self.formVerdict(
      comparison, context: context, state: &state
    )
    guard verdict.isEmpty else { return false }
    state.allowedAddedObjects.formUnion(afterForm.addedContainers)
    return true
  }
}
