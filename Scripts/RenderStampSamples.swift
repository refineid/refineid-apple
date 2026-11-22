// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
// Usage: Scripts/render-stamp-samples.py [output-directory] [rotation-degrees]
// Generates standard-font PDFs using the production renderer for visual comparison.
import AppKit
import Foundation
import PDFKit

enum RenderError: LocalizedError {
  case invalidRotation(Double)
  case renderFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidRotation(let angle):
      return "Invalid rotation angle \(angle) degrees."
    case .renderFailed(let reason):
      return "Failed to render stamp: \(reason)"
    }
  }
}

@main
enum RenderStampSamples {
  static func main() throws {
    guard CommandLine.arguments.count > 1 else {
      FileHandle.standardError.write(
        Data("Usage: Scripts/render-stamp-samples.py [output-directory] [rotation-degrees]\n".utf8)
      )
      exit(2)
    }
    let destination = CommandLine.arguments[1]
    let requestedAngle = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) : nil
    if CommandLine.arguments.count > 2,
      requestedAngle.map({ PdfStampRenderer.rotationDegreesRange.contains($0) }) != true
    {
      throw RenderError.invalidRotation(requestedAngle ?? 0)
    }
    for language in ["en", "fi", "sv"] {
      let angle = requestedAngle ?? Double.random(in: PdfStampRenderer.rotationDegreesRange)
      let mark = PdfStampRenderer.stampMark(
        locale: Locale(identifier: language), rotationDegrees: angle)
      let operators = "q 1 0 0 1 72 72 cm\n" + mark.operators + "Q\n"
      print(String(format: "%@: %.2f degrees counterclockwise", language, angle))
      let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 144 144] "
          + "/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
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
      try data.write(
        to: URL(fileURLWithPath: "\(destination)/signature-stamp-\(language)-tilted.pdf"))
      guard let document = PDFDocument(data: data), let page = document.page(at: 0) else {
        throw RenderError.renderFailed("PDF generation failed for \(language)")
      }
      guard
        let bitmap = NSBitmapImageRep(
          bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 1200, bitsPerSample: 8,
          samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
          bytesPerRow: 0, bitsPerPixel: 0
        ),
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
      else {
        throw RenderError.renderFailed("Bitmap context allocation failed")
      }
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = context
      context.cgContext.setFillColor(NSColor.white.cgColor)
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 1200, height: 1200))
      context.cgContext.scaleBy(x: 1200 / 144, y: 1200 / 144)
      page.draw(with: .mediaBox, to: context.cgContext)
      NSGraphicsContext.restoreGraphicsState()
      guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw RenderError.renderFailed("PNG representation encoding failed")
      }
      try pngData.write(
        to: URL(fileURLWithPath: "\(destination)/signature-stamp-\(language)-tilted.png")
      )
    }
  }
}
