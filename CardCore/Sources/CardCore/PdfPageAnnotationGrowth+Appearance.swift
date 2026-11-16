// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Widget geometry, `/MediaBox` inheritance, and `/AP` form XObject
/// validation for post-signature widgets.
extension PdfPageAnnotationGrowth {
  /// Indirect references discovered inside a resource dictionary.
  private struct ReferencedSubgraph {
    /// Failed parse or excessive nesting depth.
    static let invalid = Self(isValid: false, references: [])

    /// Whether the dictionary nesting was within bounds.
    let isValid: Bool

    /// Indirect references appearing in the dictionary's values.
    let references: [PdfValidationStore.StoreReference]
  }

  /// Axis-aligned bounding box ordered into minimum and maximum corners.
  private struct NormalizedBox {
    let minX: Double
    let maxX: Double
    let minY: Double
    let maxY: Double
  }

  /// Allowed appearance state keys in `/AP` (ISO 32000-1 §12.5.5).
  private static let allowedAppearanceKeys: Set<String> = ["N", "R", "D"]

  /// Forbidden `/Type` values inside an appearance stream's resource
  /// subgraph.
  private static let forbiddenAppearanceTypes: Set<String> = [
    "/Action", "/Annot", "/Catalog", "/Filespec", "/Page", "/Pages", "/Sig",
  ]

  /// Maximum resource object count traversed under one appearance stream.
  private static let maximumResourceGraphObjects = 64

  /// Maximum inline dictionary nesting depth inside resource dictionaries.
  private static let maximumDictionaryNestingDepth = 16

  /// Validates widget `/Rect` and `/AP` against the bound signature's
  /// kind and cryptographic status.
  internal static func validateVisibilityAndAppearance(
    widgetSyntax: PdfValidationStore.DictionarySyntax,
    pageBox: [Double],
    candidate: PdfSignedContentAnalysis.PostSignatureCandidate,
    input: ValidationInput
  ) -> AppearanceApproval {
    guard let rectEntry = widgetSyntax.entry(named: "Rect") else {
      return .rejected
    }
    let rect = PdfValidationStore.TypedValues.realArray(
      in: widgetSyntax.value(of: rectEntry)
    )
    guard rect.count == PdfValues.boxCorners else { return .rejected }
    let width = abs(
      rect[PdfValues.boxUpperRightX] - rect[PdfValues.boxLowerLeftX]
    )
    let height = abs(
      rect[PdfValues.boxUpperRightY] - rect[PdfValues.boxLowerLeftY]
    )
    let hasAppearance =
      widgetSyntax.entry(named: "AP") != nil
      || widgetSyntax.entry(named: "AS") != nil
    if width == 0, height == 0, !hasAppearance {
      return .empty
    }
    guard
      !candidate.isTimestamp,
      candidate.isCryptographicallyVerified,
      Self.fitsWithinPageAllowance(rect: rect, pageBox: pageBox)
    else {
      return .rejected
    }
    guard let apEntry = widgetSyntax.entry(named: "AP") else {
      return .empty
    }
    return Self.approvedAppearanceSubgraph(
      apValue: widgetSyntax.value(of: apEntry),
      newest: input.newest,
      document: input.document,
      signed: input.signed
    )
  }

  /// Validates `/AP` (`/N`, plus optional `/R` and `/D`) and collects
  /// newly added objects reachable from `/Subtype /Form` streams.
  internal static func approvedAppearanceSubgraph(
    apValue: String,
    newest: PdfDocumentIndex,
    document: Data,
    signed: PdfDocumentIndex
  ) -> AppearanceApproval {
    var allowed: Set<Int> = []
    let apSyntax: PdfValidationStore.DictionarySyntax
    if let direct = try? PdfValidationStore.DictionarySyntax(apValue) {
      apSyntax = direct
    } else if let indirect = try? PdfValidationStore.ValueParser.reference(
      in: apValue
    ),
      newest.locations[indirect.number]?.generation == indirect.generation,
      signed.locations[indirect.number] != nil || indirect.generation == 0,
      let apBody = newest.comparisonBody(of: indirect.number, in: document),
      !PdfTypeEntry.hasStream(apBody),
      let parsed = try? PdfValidationStore.DictionarySyntax(apBody)
    {
      if signed.locations[indirect.number] == nil {
        allowed.insert(indirect.number)
      }
      apSyntax = parsed
    } else {
      return .rejected
    }
    let stateNames = Set(apSyntax.entries.map(\.name))
    guard
      apSyntax.entry(named: "N") != nil,
      stateNames.isSubset(of: Self.allowedAppearanceKeys)
    else {
      return .rejected
    }
    for entry in apSyntax.entries {
      let approval = Self.approvedAppearanceFormEntry(
        apSyntax.value(of: entry),
        newest: newest,
        document: document,
        signed: signed
      )
      guard approval.isAllowed else { return .rejected }
      allowed.formUnion(approval.allowedObjects)
    }
    return AppearanceApproval(isAllowed: true, allowedObjects: allowed)
  }

  /// Validates one `/N`, `/R`, or `/D` entry referencing a `/Subtype /Form`
  /// appearance stream.
  private static func approvedAppearanceFormEntry(
    _ value: String,
    newest: PdfDocumentIndex,
    document: Data,
    signed: PdfDocumentIndex
  ) -> AppearanceApproval {
    guard
      let formReference = try? PdfValidationStore.ValueParser.reference(
        in: value
      ),
      newest.locations[formReference.number]?.generation
        == formReference.generation,
      let formBody = newest.comparisonBody(
        of: formReference.number, in: document
      ),
      PdfTypeEntry.hasStream(formBody),
      PdfTypeEntry.value(of: "Subtype", in: formBody) == "/Form"
    else {
      return .rejected
    }
    if signed.locations[formReference.number] != nil {
      return .empty
    }
    guard formReference.generation == 0 else { return .rejected }
    return Self.collectResourceSubgraph(
      startingAt: formReference.number,
      newest: newest,
      document: document,
      signed: signed
    )
  }

  /// Resolves a page's `/MediaBox`, walking `/Parent` nodes when
  /// inherited and falling back to A4 when unstated.
  internal static func resolvedMediaBox(
    of pageBody: String,
    index: PdfDocumentIndex,
    document: Data
  ) -> [Double] {
    var currentBody: String? = pageBody
    for _ in 0..<PdfValues.pageTreeDepthLimit {
      guard let body = currentBody else { break }
      if let syntax = PdfTypeEntry.dictionarySyntax(of: body),
        let entry = syntax.entry(named: "MediaBox")
      {
        let resolved = Self.boxArray(
          in: syntax.value(of: entry), index: index, document: document
        )
        if resolved.count == PdfValues.boxCorners {
          return resolved
        }
      }
      guard let parent = index.verifiedReference(named: "Parent", in: body)
      else {
        break
      }
      currentBody = index.comparisonBody(of: parent, in: document)
    }
    return [0, 0, PdfValues.a4Width, PdfValues.a4Height]
  }

  /// Resolves a direct or indirect four-number box array.
  private static func boxArray(
    in value: String,
    index: PdfDocumentIndex,
    document: Data
  ) -> [Double] {
    let direct = PdfValidationStore.TypedValues.realArray(in: value)
    if direct.count == PdfValues.boxCorners { return direct }
    guard
      let reference = try? PdfValidationStore.ValueParser.reference(in: value),
      index.locations[reference.number]?.generation == reference.generation,
      let body = index.comparisonBody(of: reference.number, in: document)
    else {
      return []
    }
    return PdfValidationStore.TypedValues.realArray(in: body)
  }

  /// Whether `rect` sits inside `pageBox` and covers no more than
  /// `PdfValues.maximumPostSignatureWidgetPageFraction` of its area.
  private static func fitsWithinPageAllowance(
    rect: [Double],
    pageBox: [Double]
  ) -> Bool {
    guard
      rect.count == PdfValues.boxCorners,
      pageBox.count == PdfValues.boxCorners,
      rect.allSatisfy(\.isFinite),
      pageBox.allSatisfy(\.isFinite)
    else {
      return false
    }
    let page = Self.normalizedBox(pageBox)
    let pageWidth = page.maxX - page.minX
    let pageHeight = page.maxY - page.minY
    let pageArea = pageWidth * pageHeight
    guard pageWidth.isFinite, pageHeight.isFinite, pageArea.isFinite, pageArea > 0
    else {
      return false
    }
    let widget = Self.normalizedBox(rect)
    guard
      widget.minX >= page.minX,
      widget.maxX <= page.maxX,
      widget.minY >= page.minY,
      widget.maxY <= page.maxY
    else {
      return false
    }
    let rectArea = (widget.maxX - widget.minX) * (widget.maxY - widget.minY)
    guard rectArea.isFinite else { return false }
    return rectArea
      <= pageArea * PdfValues.maximumPostSignatureWidgetPageFraction
  }

  /// Orders a four-number PDF box into `(minX, maxX, minY, maxY)`.
  private static func normalizedBox(_ box: [Double]) -> NormalizedBox {
    NormalizedBox(
      minX: min(box[PdfValues.boxLowerLeftX], box[PdfValues.boxUpperRightX]),
      maxX: max(box[PdfValues.boxLowerLeftX], box[PdfValues.boxUpperRightX]),
      minY: min(box[PdfValues.boxLowerLeftY], box[PdfValues.boxUpperRightY]),
      maxY: max(box[PdfValues.boxLowerLeftY], box[PdfValues.boxUpperRightY])
    )
  }

  /// Traverses newly added resource objects under an appearance stream,
  /// rejecting actions, scripts, or document-structure types.
  private static func collectResourceSubgraph(
    startingAt root: Int,
    newest: PdfDocumentIndex,
    document: Data,
    signed: PdfDocumentIndex
  ) -> AppearanceApproval {
    var visited: Set<Int> = []
    var queue: [Int] = [root]
    while let current = queue.popLast() {
      guard visited.insert(current).inserted else { continue }
      guard
        visited.count <= Self.maximumResourceGraphObjects,
        newest.locations[current]?.generation == 0,
        let body = newest.comparisonBody(of: current, in: document)
      else {
        return .rejected
      }
      let next = Self.addedResourceChildren(
        in: body, newest: newest, signed: signed
      )
      guard next.isValid else { return .rejected }
      queue.append(contentsOf: next.references.map(\.number))
    }
    return AppearanceApproval(isAllowed: true, allowedObjects: visited)
  }

  /// Validates one resource object's dictionary and returns its newly
  /// added child references.
  private static func addedResourceChildren(
    in body: String,
    newest: PdfDocumentIndex,
    signed: PdfDocumentIndex
  ) -> ReferencedSubgraph {
    guard let syntax = PdfTypeEntry.dictionarySyntax(of: body) else {
      return ReferencedSubgraph(isValid: true, references: [])
    }
    guard Self.containsNoForbiddenKeys(syntax) else { return .invalid }
    if let type = PdfTypeEntry.value(of: "Type", in: body),
      Self.forbiddenAppearanceTypes.contains(type)
    {
      return .invalid
    }
    let children = Self.referencedSubgraph(in: syntax, depth: 0)
    guard children.isValid else { return .invalid }
    var added: [PdfValidationStore.StoreReference] = []
    for child in children.references {
      guard newest.locations[child.number]?.generation == child.generation
      else {
        return .invalid
      }
      if signed.locations[child.number] == nil {
        guard child.generation == 0 else { return .invalid }
        added.append(child)
      }
    }
    return ReferencedSubgraph(isValid: true, references: added)
  }

  /// Collects indirect references appearing in a dictionary's values up to
  /// `Self.maximumDictionaryNestingDepth`.
  private static func referencedSubgraph(
    in syntax: PdfValidationStore.DictionarySyntax,
    depth: Int
  ) -> ReferencedSubgraph {
    guard depth < Self.maximumDictionaryNestingDepth else { return .invalid }
    var found: [PdfValidationStore.StoreReference] = []
    for entry in syntax.entries {
      let value = syntax.value(of: entry)
      if let single = try? PdfValidationStore.ValueParser.reference(in: value) {
        found.append(single)
      } else if let nested = try? PdfValidationStore.DictionarySyntax(value) {
        let sub = Self.referencedSubgraph(in: nested, depth: depth + 1)
        guard sub.isValid else { return .invalid }
        found.append(contentsOf: sub.references)
      } else {
        let list = PdfObjectReferences.strictReferences(in: value)
        if list.isValid {
          found.append(contentsOf: list.references)
        }
      }
    }
    return ReferencedSubgraph(isValid: true, references: found)
  }
}
