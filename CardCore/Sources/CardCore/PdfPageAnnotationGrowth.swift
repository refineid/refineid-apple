// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Validates signature widgets appended to a page's `/Annots` after an
/// earlier signature (ISO 32000-1 §12.5.6.19, §12.7.4.5).
internal enum PdfPageAnnotationGrowth {
  /// The outcome of validating a page's post-signature `/Annots` list.
  internal struct GrowthOutcome {
    /// Failed validation.
    internal static let rejected = Self(
      isAllowed: false,
      widgetBindings: [:],
      fieldBindings: [:],
      allowedObjects: []
    )

    /// Whether `/Annots` kept all original entries in order and added
    /// only valid post-signature widgets.
    internal let isAllowed: Bool

    /// Map from post-signature object number to widget object number.
    internal let widgetBindings: [Int: Int]

    /// Map from post-signature object number to `/FT /Sig` field number.
    internal let fieldBindings: [Int: Int]

    /// Newly added indirect objects authorized by these widgets.
    internal let allowedObjects: Set<Int>
  }

  /// Outcome of validating a widget's `/Rect` and `/AP` subgraph.
  internal struct AppearanceApproval {
    /// Failed appearance validation.
    internal static let rejected = Self(isAllowed: false, allowedObjects: [])

    /// Allowed with no newly added appearance objects.
    internal static let empty = Self(isAllowed: true, allowedObjects: [])

    /// Whether the widget's geometry and appearance are permitted.
    internal let isAllowed: Bool

    /// Newly added indirect objects inside `/AP` and `/Subtype /Form`.
    internal let allowedObjects: Set<Int>
  }

  /// Inputs required to validate newly appended widgets on one page.
  internal struct ValidationInput {
    /// The newest cross-reference index.
    internal let newest: PdfDocumentIndex

    /// The full PDF bytes.
    internal let document: Data

    /// The signed revision's cross-reference index.
    internal let signed: PdfDocumentIndex

    /// The page dictionary body in the newest view.
    internal let pageBody: String

    /// Eligible post-signature dictionaries keyed by object number.
    internal let postSignatures: [Int: PdfSignedContentAnalysis.PostSignatureCandidate]
  }

  /// Approved binding and authorized object set for one widget.
  private struct ApprovedWidget {
    let signatureNumber: Int
    let fieldNumber: Int
    let allowedObjects: Set<Int>
  }

  /// Dictionary keys forbidden on post-signature widgets and fields.
  internal static let forbiddenActionKeys: Set<String> = [
    "A", "AA", "Dest", "JS", "JavaScript", "Launch",
  ]

  /// Validates that `grownValue` preserves `keptValue` as a prefix and
  /// appends only valid post-signature signature widgets.
  internal static func validateGrowth(
    from keptValue: String,
    to grownValue: String,
    input: ValidationInput
  ) -> GrowthOutcome {
    let kept = PdfObjectReferences.strictReferences(in: keptValue)
    let grown = PdfObjectReferences.strictReferences(in: grownValue)
    guard
      kept.isValid,
      grown.isValid,
      Array(grown.references.prefix(kept.references.count)) == kept.references
    else {
      return .rejected
    }
    let pageBox = Self.resolvedMediaBox(
      of: input.pageBody, index: input.newest, document: input.document
    )
    var widgets: [Int: Int] = [:]
    var fields: [Int: Int] = [:]
    var allowed: Set<Int> = []
    for reference in grown.references.dropFirst(kept.references.count) {
      guard
        reference.generation == 0,
        let approved = Self.approveWidget(
          number: reference.number,
          pageBox: pageBox,
          input: input
        ),
        widgets[approved.signatureNumber] == nil,
        fields[approved.signatureNumber] == nil
          || fields[approved.signatureNumber] == approved.fieldNumber
      else {
        return .rejected
      }
      widgets[approved.signatureNumber] = reference.number
      fields[approved.signatureNumber] = approved.fieldNumber
      allowed.formUnion(approved.allowedObjects)
    }
    return GrowthOutcome(
      isAllowed: true,
      widgetBindings: widgets,
      fieldBindings: fields,
      allowedObjects: allowed
    )
  }

  /// Checks that `syntax` carries no interactive action or script keys.
  internal static func containsNoForbiddenKeys(
    _ syntax: PdfValidationStore.DictionarySyntax
  ) -> Bool {
    syntax.entries.allSatisfy { entry in
      !Self.forbiddenActionKeys.contains(entry.name)
    }
  }

  /// Validates a single newly added widget object on a page.
  private static func approveWidget(
    number: Int,
    pageBox: [Double],
    input: ValidationInput
  ) -> ApprovedWidget? {
    guard
      input.newest.locations[number]?.generation == 0,
      input.signed.locations[number] == nil,
      let body = input.newest.comparisonBody(of: number, in: input.document),
      !PdfTypeEntry.hasStream(body),
      let widgetSyntax = PdfTypeEntry.dictionarySyntax(of: body),
      PdfTypeEntry.value(of: "Subtype", in: body) == "/Widget",
      Self.containsNoForbiddenKeys(widgetSyntax)
    else {
      return nil
    }
    guard
      let resolvedField = Self.resolveWidgetField(
        widgetNumber: number,
        widgetBody: body,
        widgetSyntax: widgetSyntax,
        input: input
      ),
      let candidate = input.postSignatures[resolvedField.signatureNumber]
    else {
      return nil
    }
    var allowed: Set<Int> = [number]
    if input.signed.locations[resolvedField.fieldNumber] == nil {
      allowed.insert(resolvedField.fieldNumber)
    }
    let appearance = Self.validateVisibilityAndAppearance(
      widgetSyntax: widgetSyntax,
      pageBox: pageBox,
      candidate: candidate,
      input: input
    )
    guard appearance.isAllowed else { return nil }
    allowed.formUnion(appearance.allowedObjects)
    return ApprovedWidget(
      signatureNumber: resolvedField.signatureNumber,
      fieldNumber: resolvedField.fieldNumber,
      allowedObjects: allowed
    )
  }

  /// Resolves the `/FT /Sig` field and its `/V` signature reference.
  private static func resolveWidgetField(
    widgetNumber: Int,
    widgetBody: String,
    widgetSyntax: PdfValidationStore.DictionarySyntax,
    input: ValidationInput
  ) -> (fieldNumber: Int, signatureNumber: Int)? {
    let fieldNumber: Int
    let fieldBody: String
    if widgetSyntax.entry(named: "Parent") != nil {
      guard
        let parentRef = PdfDocumentIndex.fullReference(
          named: "Parent", in: widgetBody
        ),
        let parentNumber = input.newest.verifiedReference(
          named: "Parent", in: widgetBody
        ),
        input.signed.locations[parentNumber] != nil || parentRef.generation == 0,
        let parentBody = input.newest.comparisonBody(
          of: parentNumber, in: input.document
        ),
        !PdfTypeEntry.hasStream(parentBody),
        let parentSyntax = PdfTypeEntry.dictionarySyntax(of: parentBody),
        Self.containsNoForbiddenKeys(parentSyntax)
      else {
        return nil
      }
      fieldNumber = parentNumber
      fieldBody = parentBody
    } else {
      fieldNumber = widgetNumber
      fieldBody = widgetBody
    }
    guard
      PdfTypeEntry.value(of: "FT", in: fieldBody) == "/Sig",
      let signatureNumber = input.newest.zeroGenVerifiedReference(
        named: "V", in: fieldBody
      ),
      input.signed.locations[signatureNumber] == nil
    else {
      return nil
    }
    return (fieldNumber, signatureNumber)
  }
}
