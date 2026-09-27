import AppKit
// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
// Usage: Scripts/render-stamp-samples.sh [output-directory]
// Generates standard-font PDFs using the production renderer for visual comparison.
import Foundation
import PDFKit

@main
struct RenderStampSamples {
  static func main() throws {
    let destination = CommandLine.arguments[1]
    for language in ["en", "fi", "sv"] {
      let operators =
        "q 1 0 0 1 72 72 cm\n"
        + PdfStampRenderer.generateStampOperators(locale: Locale(identifier: language)) + "Q\n"
      let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 144 144] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
        "<< /Length \(operators.utf8.count) >>\nstream\n\(operators)endstream",
      ]
      var pdf = "%PDF-1.4\n"
      var offsets = [0]
      for (index, object) in objects.enumerated() {
        offsets.append(pdf.utf8.count)
        pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
      }
      let start = pdf.utf8.count
      pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
      for offset in offsets.dropFirst() { pdf += String(format: "%010d 00000 n \n", offset) }
      pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(start)\n%%EOF\n"
      let data = Data(pdf.utf8)
      try data.write(to: URL(fileURLWithPath: "\(destination)/signature-stamp-\(language).pdf"))
      guard let document = PDFDocument(data: data), let page = document.page(at: 0) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 1200, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
      )!
      let context = NSGraphicsContext(bitmapImageRep: bitmap)!
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = context
      context.cgContext.setFillColor(NSColor.white.cgColor)
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 1200, height: 1200))
      context.cgContext.scaleBy(x: 1200 / 144, y: 1200 / 144)
      page.draw(with: .mediaBox, to: context.cgContext)
      NSGraphicsContext.restoreGraphicsState()
      try bitmap.representation(using: .png, properties: [:])!.write(
        to: URL(fileURLWithPath: "\(destination)/signature-stamp-\(language).png")
      )
    }
  }
}
