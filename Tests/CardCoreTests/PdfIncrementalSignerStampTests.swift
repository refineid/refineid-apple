// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

#if canImport(PDFKit)
  import PDFKit
#endif

/// Invariants for visual signature stamp widgets on PDF documents.
@Suite
internal struct PdfIncrementalSignerStampTests {
  private static var claim: PdfIncrementalSigner.SignatureClaim {
    PdfIncrementalSigner.SignatureClaim(
      signedAt: Date(timeIntervalSince1970: 0), reason: nil, location: nil
    )
  }

  private static func pdf(catalog: String) -> Data {
    var text = "%PDF-1.7\n"
    var offsets: [Int] = []
    for (number, body) in [
      (1, catalog),
      (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
      (3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>"),
    ] {
      offsets.append(text.utf8.count)
      text += "\(number) 0 obj\n\(body)\nendobj\n"
    }
    let xrefOffset = text.utf8.count
    text += "xref\n0 4\n0000000000 65535 f \n"
    for offset in offsets {
      text += String(format: "%010d 00000 n \n", offset)
    }
    text += "trailer\n<< /Size 4 /Root 1 0 R >>\n"
    text += "startxref\n\(xrefOffset)\n%%EOF\n"
    return Data(text.utf8)
  }

  private static func text(_ document: Data) -> String {
    String(bytes: document, encoding: .isoLatin1) ?? ""
  }

  @Test
  internal func signatureWidgetIncludesPageReferenceAndStampMarker() throws {
    let original = Self.pdf(catalog: "<< /Type /Catalog /Pages 2 0 R >>")
    let mark = PdfStampRenderer.stampMark(locale: Locale(identifier: "fi_FI"))
    let prepared = try PdfIncrementalSigner.prepare(
      original, revision: .signature(Self.claim), appending: mark
    )
    let filled = try prepared.filled(with: WireHex.data("30030101FF"))
    let text = Self.text(filled)
    #expect(text.contains("/P 3 0 R"))
    #expect(text.contains("/AP << /N 6 0 R >>"))
    #expect(text.contains("/RefineIDStamp true"))
    #expect(text.contains("/F 132"))
    #if canImport(PDFKit)
      let doc = PDFDocument(data: filled)
      let page = doc?.page(at: 0)
      #expect(page?.annotations.count == 1)
      #expect(page?.annotations.first?.type == "Widget")
    #endif
  }

  @Test
  internal func stampWithIndirectAnnotationsArrayReissuesAnnotsObject() throws {
    var text = "%PDF-1.7\n"
    var offsets: [Int] = []
    for (number, body) in [
      (1, "<< /Type /Catalog /Pages 2 0 R >>"),
      (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
      (3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Annots 4 0 R >>"),
      (4, "[ ]"),
    ] {
      offsets.append(text.utf8.count)
      text += "\(number) 0 obj\n\(body)\nendobj\n"
    }
    let xrefOffset = text.utf8.count
    text += "xref\n0 5\n0000000000 65535 f \n"
    for offset in offsets {
      text += String(format: "%010d 00000 n \n", offset)
    }
    text += "trailer\n<< /Size 5 /Root 1 0 R >>\n"
    text += "startxref\n\(xrefOffset)\n%%EOF\n"
    let original = Data(text.utf8)

    let mark = PdfStampRenderer.stampMark(locale: Locale(identifier: "fi_FI"))
    let prepared = try PdfIncrementalSigner.prepare(
      original, revision: .signature(Self.claim), appending: mark
    )
    let filled = try prepared.filled(with: WireHex.data("30030101FF"))
    let signedText = Self.text(filled)
    #expect(signedText.contains("4 0 obj\n[  6 0 R]\nendobj"))
    #expect(signedText.contains("/P 3 0 R"))
    #if canImport(PDFKit)
      let doc = PDFDocument(data: filled)
      let page = doc?.page(at: 0)
      #expect(page?.annotations.count == 1)
      #expect(page?.annotations.first?.type == "Widget")
    #endif
  }
}
