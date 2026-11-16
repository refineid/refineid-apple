// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Catalog, interactive-form, page, and pre-existing signature-field
/// rules for post-signature PDF revisions.
extension PdfSignedContentAnalysis {
  /// Catalog keys a later revision may add or update when `DocMDP` does
  /// not forbid changes.
  private static let standardCatalogKeys: Set<String> = [
    "DSS", "AcroForm", "Metadata",
  ]

  /// Catalog keys a later revision may add or update under no-changes
  /// `DocMDP`.
  private static let docMdpCatalogKeys: Set<String> = ["DSS", "AcroForm"]

  /// Interactive-form keys a later revision may add or update.
  private static let formKeys: Set<String> = ["Fields", "SigFlags"]

  /// Keys a pre-existing empty `/FT /Sig` field may gain when filled.
  private static let signatureFieldFillKeys: Set<String> = ["V", "AP", "AS"]

  /// Keys a pre-existing split `/Subtype /Widget` may gain when its
  /// parent `/FT /Sig` field is filled.
  private static let splitWidgetFillKeys: Set<String> = ["AP", "AS"]

  /// Validates changes to the document catalog.
  internal static func catalogVerdict(
    _ comparison: ObjectComparison,
    context: Context,
    state: inout VerificationState
  ) -> Set<SignedContentChange> {
    let allowedKeys =
      context.hasNoChangesDocMdp
      ? Self.docMdpCatalogKeys : Self.standardCatalogKeys
    guard
      !PdfTypeEntry.hasStream(comparison.previous),
      !PdfTypeEntry.hasStream(comparison.body),
      comparison.differences.names.isSubset(of: allowedKeys)
    else {
      return [.documentStructure]
    }
    if comparison.differences.names.contains("DSS"),
      !Self.catalogDssGrowsOnly(
        from: comparison.previous, to: comparison.body, context: context
      )
    {
      return [.documentStructure]
    }
    if comparison.differences.names.contains("AcroForm"),
      !Self.catalogAcroFormGrowsOnly(
        from: comparison.previous,
        to: comparison.body,
        context: context,
        state: &state
      )
    {
      return [.documentStructure]
    }
    if comparison.differences.names.contains("Metadata"),
      !Self.catalogMetadataIsValid(
        in: comparison.body, context: context, state: &state
      )
    {
      return [.documentStructure]
    }
    return []
  }

  /// Validates a rewritten `/Page` object.
  internal static func pageVerdict(
    _ comparison: ObjectComparison,
    context: Context,
    state: inout VerificationState
  ) -> Set<SignedContentChange> {
    guard
      PdfTypeEntry.value(of: "Type", in: comparison.previous) == "/Page",
      PdfTypeEntry.value(of: "Type", in: comparison.body) == "/Page",
      !PdfTypeEntry.hasStream(comparison.previous),
      !PdfTypeEntry.hasStream(comparison.body),
      comparison.differences.names == ["Annots"],
      let keptAnnots = Self.resolvedArrayText(
        named: "Annots",
        in: comparison.previous,
        index: context.signed,
        document: context.signedDocument
      ),
      let grownAnnots = Self.resolvedArrayWithContainer(
        named: "Annots",
        in: comparison.body,
        context: context
      )
    else {
      return [.pageContent]
    }
    let outcome = PdfPageAnnotationGrowth.validateGrowth(
      from: keptAnnots,
      to: grownAnnots.text,
      input: PdfPageAnnotationGrowth.ValidationInput(
        newest: context.newest,
        document: context.document,
        signed: context.signed,
        pageBody: comparison.body,
        postSignatures: context.postSignatures
      )
    )
    guard
      outcome.isAllowed,
      Self.mergeBindings(
        widgets: outcome.widgetBindings,
        fields: outcome.fieldBindings,
        allowed: outcome.allowedObjects.union(grownAnnots.addedContainers),
        into: &state
      )
    else {
      return [.pageContent]
    }
    return []
  }

  /// Validates a rewritten indirect `/Annots` array against every owning
  /// page in `pageNumbers`.
  internal static func indirectAnnotsVerdict(
    previous: String,
    body: String,
    pageNumbers: [Int],
    context: Context,
    state: inout VerificationState
  ) -> Set<SignedContentChange> {
    var combinedWidgets: [Int: Int] = [:]
    var combinedFields: [Int: Int] = [:]
    var combinedAllowed: Set<Int> = []
    for pageNumber in pageNumbers {
      guard let pageBody = context.body(of: pageNumber) else {
        return [.pageContent]
      }
      let outcome = PdfPageAnnotationGrowth.validateGrowth(
        from: previous,
        to: body,
        input: PdfPageAnnotationGrowth.ValidationInput(
          newest: context.newest,
          document: context.document,
          signed: context.signed,
          pageBody: pageBody,
          postSignatures: context.postSignatures
        )
      )
      guard outcome.isAllowed else { return [.pageContent] }
      combinedWidgets = outcome.widgetBindings
      combinedFields = outcome.fieldBindings
      combinedAllowed.formUnion(outcome.allowedObjects)
    }
    guard
      pageNumbers.count == 1 || combinedWidgets.isEmpty,
      Self.mergeBindings(
        widgets: combinedWidgets,
        fields: combinedFields,
        allowed: combinedAllowed,
        into: &state
      )
    else {
      return [.pageContent]
    }
    return []
  }

  /// Validates a rewritten indirect `AcroForm` dictionary.
  internal static func formVerdict(
    _ comparison: ObjectComparison,
    context: Context,
    state: inout VerificationState
  ) -> Set<SignedContentChange> {
    guard
      !PdfTypeEntry.hasStream(comparison.previous),
      !PdfTypeEntry.hasStream(comparison.body),
      comparison.differences.names.isSubset(of: Self.formKeys)
    else {
      return [.documentStructure]
    }
    guard comparison.differences.names.contains("Fields") else { return [] }
    guard
      let keptFields = Self.resolvedArrayText(
        named: "Fields",
        in: comparison.previous,
        index: context.signed,
        document: context.signedDocument
      ),
      let grownFields = Self.resolvedArrayWithContainer(
        named: "Fields",
        in: comparison.body,
        context: context
      ),
      Self.fieldsArrayGrowsOnly(
        from: keptFields,
        to: grownFields.text,
        addedContainers: grownFields.addedContainers,
        context: context,
        state: &state
      )
    else {
      return [.documentStructure]
    }
    return []
  }

  /// Validates a rewritten indirect `/Fields` array referenced by
  /// `AcroForm`.
  internal static func indirectFieldsVerdict(
    previous: String,
    body: String,
    context: Context,
    state: inout VerificationState
  ) -> Set<SignedContentChange> {
    Self.fieldsArrayGrowsOnly(
      from: previous,
      to: body,
      addedContainers: [],
      context: context,
      state: &state
    ) ? [] : [.documentStructure]
  }

  /// Validates redefinition of a pre-existing `/FT /Sig` field or split
  /// `/Subtype /Widget`.
  internal static func signatureFieldOrWidgetRedefinitionVerdict(
    _ comparison: ObjectComparison,
    context: Context,
    state: inout VerificationState
  ) -> Verdict {
    let wasSig = PdfTypeEntry.value(of: "FT", in: comparison.previous) == "/Sig"
    let isSig = PdfTypeEntry.value(of: "FT", in: comparison.body) == "/Sig"
    let wasWidget =
      PdfTypeEntry.value(of: "Subtype", in: comparison.previous) == "/Widget"
    let isWidget =
      PdfTypeEntry.value(of: "Subtype", in: comparison.body) == "/Widget"
    if wasSig || isSig {
      return .changes(
        Self.filledSignatureFieldVerdict(
          comparison,
          isWidget: wasWidget || isWidget,
          context: context,
          state: &state
        )
      )
    }
    if wasWidget || isWidget {
      return .changes(
        Self.filledSplitWidgetVerdict(
          comparison, context: context, state: &state
        )
      )
    }
    return .unnamed
  }

  /// Validates filling a pre-existing unsigned `/FT /Sig` field once.
  private static func filledSignatureFieldVerdict(
    _ comparison: ObjectComparison,
    isWidget: Bool,
    context: Context,
    state: inout VerificationState
  ) -> Set<SignedContentChange> {
    let failure: Set<SignedContentChange> =
      isWidget ? [.pageContent] : [.documentStructure]
    guard
      !context.hasNoChangesDocMdp,
      PdfTypeEntry.value(of: "FT", in: comparison.previous) == "/Sig",
      PdfTypeEntry.value(of: "FT", in: comparison.body) == "/Sig",
      !PdfTypeEntry.hasStream(comparison.previous),
      !PdfTypeEntry.hasStream(comparison.body),
      Self.hasEmptySignatureValue(in: comparison.previous),
      comparison.differences.names.isSubset(of: Self.signatureFieldFillKeys),
      comparison.differences.names.contains("V"),
      let afterSyntax = PdfTypeEntry.dictionarySyntax(of: comparison.body),
      PdfPageAnnotationGrowth.containsNoForbiddenKeys(afterSyntax),
      let signatureNumber = context.newest.zeroGenVerifiedReference(
        named: "V", in: comparison.body
      ),
      let candidate = context.postSignatures[signatureNumber],
      !candidate.isTimestamp
    else {
      return failure
    }
    var allowed: Set<Int> = []
    if comparison.differences.names.contains("AP")
      || comparison.differences.names.contains("AS")
    {
      guard candidate.isCryptographicallyVerified else { return failure }
      if let apEntry = afterSyntax.entry(named: "AP") {
        let approval = PdfPageAnnotationGrowth.approvedAppearanceSubgraph(
          apValue: afterSyntax.value(of: apEntry),
          newest: context.newest,
          document: context.document,
          signed: context.signed
        )
        guard approval.isAllowed else { return failure }
        allowed.formUnion(approval.allowedObjects)
      }
    }
    var widgets: [Int: Int] = [:]
    if isWidget { widgets[signatureNumber] = comparison.number }
    guard
      Self.mergeBindings(
        widgets: widgets,
        fields: [signatureNumber: comparison.number],
        allowed: allowed,
        into: &state
      )
    else {
      return failure
    }
    return []
  }

  /// Validates adding an appearance to a pre-existing split `/Widget`
  /// whose parent `/FT /Sig` field was unsigned in `signed` and filled in
  /// `newest`.
  private static func filledSplitWidgetVerdict(
    _ comparison: ObjectComparison,
    context: Context,
    state: inout VerificationState
  ) -> Set<SignedContentChange> {
    guard
      !context.hasNoChangesDocMdp,
      PdfTypeEntry.value(of: "Subtype", in: comparison.previous) == "/Widget",
      PdfTypeEntry.value(of: "Subtype", in: comparison.body) == "/Widget",
      !PdfTypeEntry.hasStream(comparison.previous),
      !PdfTypeEntry.hasStream(comparison.body),
      comparison.differences.names.isSubset(of: Self.splitWidgetFillKeys),
      let afterSyntax = PdfTypeEntry.dictionarySyntax(of: comparison.body),
      PdfPageAnnotationGrowth.containsNoForbiddenKeys(afterSyntax),
      let parentNumber = context.signed.verifiedReference(
        named: "Parent", in: comparison.previous
      ),
      context.newest.verifiedReference(named: "Parent", in: comparison.body)
        == parentNumber,
      let oldParent = context.signedBody(of: parentNumber),
      PdfTypeEntry.value(of: "FT", in: oldParent) == "/Sig",
      Self.hasEmptySignatureValue(in: oldParent),
      let newParent = context.body(of: parentNumber),
      let signatureNumber = context.newest.zeroGenVerifiedReference(
        named: "V", in: newParent
      ),
      let candidate = context.postSignatures[signatureNumber],
      !candidate.isTimestamp,
      candidate.isCryptographicallyVerified
    else {
      return [.pageContent]
    }
    var allowed: Set<Int> = []
    if let apEntry = afterSyntax.entry(named: "AP") {
      let approval = PdfPageAnnotationGrowth.approvedAppearanceSubgraph(
        apValue: afterSyntax.value(of: apEntry),
        newest: context.newest,
        document: context.document,
        signed: context.signed
      )
      guard approval.isAllowed else { return [.pageContent] }
      allowed.formUnion(approval.allowedObjects)
    }
    guard
      Self.mergeBindings(
        widgets: [signatureNumber: comparison.number],
        fields: [signatureNumber: parentNumber],
        allowed: allowed,
        into: &state
      )
    else {
      return [.pageContent]
    }
    return []
  }

  /// Whether `fieldBody` has no `/V` entry or carries `/V null`.
  private static func hasEmptySignatureValue(in fieldBody: String) -> Bool {
    guard let syntax = PdfTypeEntry.dictionarySyntax(of: fieldBody) else {
      return false
    }
    guard let entry = syntax.entry(named: "V") else { return true }
    return syntax.value(of: entry) == "null"
  }
}
