// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Whether a page's annotations only gained widgets of signature
/// fields.
///
/// An annotation is drawn over the page, so one added after signing
/// changes what a reader shows: a stamp, a note or a text box saying
/// what the signer never said. Only a widget of a signature field that
/// carries a signature, which signing appends to the page it signs, may
/// follow a signature (ISO 32000-1 clause 12.7.4.5).
internal enum PdfPageAnnotationGrowth {
  /// Whether the page `body` keeps its annotations in order and only
  /// adds signed signature widgets to them.
  internal static func annotationsGrowOnly(
    from previous: String,
    to body: String,
    newest: PdfDocumentIndex,
    document: Data
  ) -> Bool {
    guard
      let before = try? PdfValidationStore.DictionarySyntax(PdfTypeEntry.dictionary(of: previous)),
      let after = try? PdfValidationStore.DictionarySyntax(PdfTypeEntry.dictionary(of: body)),
      let previousEntry = before.entry(named: "Annots"),
      let entry = after.entry(named: "Annots")
    else {
      return false
    }
    let kept = PdfObjectReferences.references(in: before.value(of: previousEntry))
    let grown = PdfObjectReferences.references(in: after.value(of: entry))
    guard Array(grown.prefix(kept.count)) == kept else { return false }
    return grown.dropFirst(kept.count).allSatisfy { reference in
      isSignedWidget(reference, newest: newest, document: document)
    }
  }

  /// Whether the `N G` reference names the widget of a field that
  /// carries a signature.
  private static func isSignedWidget(
    _ reference: String,
    newest: PdfDocumentIndex,
    document: Data
  ) -> Bool {
    guard let number = Int(reference.split(separator: " ").first ?? "") else { return false }
    guard let body = newest.body(of: number, in: document) else { return false }
    guard PdfTypeEntry.value(of: "Subtype", in: body) == "/Widget" else { return false }
    let field = parent(of: body, newest: newest, document: document) ?? body
    guard PdfTypeEntry.value(of: "FT", in: field) == "/Sig" else { return false }
    guard
      let value = PdfTypeEntry.value(of: "V", in: field),
      let signature = Int(value.drop(while: \.isWhitespace).prefix(while: \.isNumber)),
      let signatureBody = newest.body(of: signature, in: document)
    else {
      return false
    }
    return PdfTypeEntry.value(of: "ByteRange", in: signatureBody) != nil
  }

  /// A widget's parent field's body, when it names one.
  private static func parent(
    of body: String,
    newest: PdfDocumentIndex,
    document: Data
  ) -> String? {
    guard
      let value = PdfTypeEntry.value(of: "Parent", in: body),
      let number = Int(value.drop(while: \.isWhitespace).prefix(while: \.isNumber))
    else {
      return nil
    }
    return newest.body(of: number, in: document)
  }
}
