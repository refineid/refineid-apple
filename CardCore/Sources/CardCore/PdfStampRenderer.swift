// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CoreText
import Foundation

/// Renders the visual red electronic signature stamp.
///
/// The stamp advises verifying the electronic signature of the signed file.
/// Vector operators center on the origin and use standard PDF typography.
public enum PdfStampRenderer {
  internal struct StampTexts: Sendable {
    internal let middleLines: [String]
    internal let topBorderText: String
    internal let bottomBorderText: String
  }

  internal struct TextMetrics {
    internal let advance: Double
    internal let bounds: CGRect
  }

  internal struct CenterLine {
    internal let text: String
    internal let fontSize: Double
    internal let origin: CGPoint
    internal let bounds: CGRect
  }

  /// The outer circular radius of the stamp in points.
  public static let stampRadius = 64.0
  /// The bleed margin in points for line strokes.
  public static let stampBleed = 2.0
  /// The total reach from center including stroke bleed.
  public static let stampReach = 66.0

  private static let borderInnerRadius = 48.0
  private static let inkColor = "0.7765 0.1569 0.1569"
  private static let circleKappa = 0.5522847498307935

  private static let outerRingLineWidth = 1.8
  private static let borderSeparatorLineWidth = 0.9
  private static let arcFontSize = 4.8
  private static let arcBandCenterRadius = 56.0
  private static let arcSweepDegrees = 156.0
  private static let semicircleDegrees = 180.0
  private static let arcSweep = arcSweepDegrees * Double.pi / semicircleDegrees
  private static let rightAngle = Double.pi * half
  private static let half = 0.5
  private static let centerCommandFontSize = 11.0
  private static let centerBodyFontSize = 9.0
  private static let centerLineGap = 4.0
  private static let centerWidthFraction = 0.82
  private static let diameterFactor = 2.0
  private static let bulletRadius = 0.55
  private static let fontName = "Helvetica-Bold"

  private static let asciiPrintableMin: UInt8 = 32
  private static let asciiPrintableMax: UInt8 = 126
  private static let octalByteModulus = 256

  private static let specialEscapes: [Character: String] = [
    "(": "\\(",
    ")": "\\)",
    "\\": "\\\\",
    "\u{00E4}": "\\344",
    "\u{00F6}": "\\366",
    "\u{00E5}": "\\345",
    "\u{00C4}": "\\304",
    "\u{00D6}": "\\326",
    "\u{00C5}": "\\305",
    "\u{2022}": "\\225",
  ]

  internal static func textMetrics(_ text: String, fontSize: Double) -> TextMetrics {
    let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(
        string: text,
        attributes: [
          .init(kCTFontAttributeName as String): font,
          .init(kCTKernAttributeName as String): 0,
        ])
    )
    return TextMetrics(
      advance: CTLineGetTypographicBounds(line, nil, nil, nil),
      bounds: CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    )
  }

  /// Creates a ready-to-place stamp mark with the localized advice.
  public static func stampMark(locale: Locale = .current) -> StampMark {
    StampMark(
      radius: stampRadius,
      operators: generateStampOperators(locale: locale)
    )
  }

  /// Generates the PDF graphics stream operators drawing the complete stamp.
  public static func generateStampOperators(locale: Locale = .current) -> String {
    var output = "q\n"
    output += "\(inkColor) RG \(inkColor) rg\n"
    appendRings(into: &output)
    let stampTexts = resolveStampTexts(locale: locale)
    appendTopArc(into: &output, text: stampTexts.topBorderText)
    appendBottomArc(into: &output, text: stampTexts.bottomBorderText)
    appendBullets(into: &output)
    appendCenterLines(into: &output, lines: stampTexts.middleLines)
    output += "Q\n"
    return output
  }

  private static func appendRings(into output: inout String) {
    output += "\(outerRingLineWidth) w\n"
    appendCircle(into: &output, radius: stampRadius)
    output += "S\n"

    output += "\(borderSeparatorLineWidth) w\n"
    appendCircle(into: &output, radius: borderInnerRadius)
    output += "S\n"
  }

  private static func appendTopArc(into output: inout String, text: String) {
    appendArc(into: &output, text: text, top: true)
  }

  private static func appendBottomArc(into output: inout String, text: String) {
    appendArc(into: &output, text: text, top: false)
  }

  private static func appendArc(into output: inout String, text: String, top: Bool) {
    let metrics = textMetrics(text, fontSize: arcFontSize)
    let radius = arcBandCenterRadius + (top ? -metrics.bounds.midY : metrics.bounds.midY)
    let advances = text.map { textMetrics(String($0), fontSize: arcFontSize).advance }
    let totalAdvance = advances.reduce(0, +)
    let tracking = (radius * arcSweep - totalAdvance) / Double(max(text.count - 1, 1))
    let length = totalAdvance + tracking * Double(max(text.count - 1, 0))
    var distance = -length * half
    let direction = top ? -1.0 : 1.0
    let centerAngle = top ? rightAngle : -rightAngle

    output += "BT\n"
    output += String(format: "/F1 %.2f Tf\n", arcFontSize)
    for (character, advance) in zip(text, advances) {
      let angle = centerAngle + direction * (distance + advance * half) / radius
      let textAngle = angle + (top ? -rightAngle : rightAngle)
      let cosA = cos(textAngle)
      let sinA = sin(textAngle)
      let pointX = radius * cos(angle) - advance * half * cosA
      let pointY = radius * sin(angle) - advance * half * sinA
      output += String(
        format: "%.4f %.4f %.4f %.4f %.2f %.2f Tm\n",
        cosA, sinA, -sinA, cosA, pointX, pointY
      )
      output += "(\(escapePdfString(character))) Tj\n"
      distance += advance + tracking
    }
    output += "ET\n"
  }

  private static func appendBullets(into output: inout String) {
    for pointX in [-arcBandCenterRadius, arcBandCenterRadius] {
      output += String(format: "1 0 0 1 %.2f 0 cm\n", pointX)
      appendCircle(into: &output, radius: bulletRadius)
      output += "f\n"
      output += String(format: "1 0 0 1 %.2f 0 cm\n", -pointX)
    }
  }

  internal static func centerLayout(lines: [String]) -> [CenterLine] {
    var baseline = 0.0
    var layout: [CenterLine] = []
    for (index, text) in lines.enumerated() {
      let preferredSize = index == 0 ? centerCommandFontSize : centerBodyFontSize
      let preferred = textMetrics(text, fontSize: preferredSize)
      let maxWidth = borderInnerRadius * diameterFactor * centerWidthFraction
      let fontSize = min(preferredSize, preferredSize * maxWidth / preferred.bounds.width)
      let metrics = textMetrics(text, fontSize: fontSize)
      if let previous = layout.last {
        baseline = previous.origin.y + previous.bounds.minY - centerLineGap - metrics.bounds.maxY
      }
      layout.append(
        CenterLine(
          text: text, fontSize: fontSize,
          origin: CGPoint(x: -metrics.bounds.midX, y: baseline), bounds: metrics.bounds
        ))
    }
    let inkBounds = layout.reduce(CGRect.null) { bounds, line in
      bounds.union(line.bounds.offsetBy(dx: line.origin.x, dy: line.origin.y))
    }
    return layout.map { line in
      CenterLine(
        text: line.text, fontSize: line.fontSize,
        origin: CGPoint(x: line.origin.x, y: line.origin.y - inkBounds.midY), bounds: line.bounds
      )
    }
  }

  private static func appendCenterLines(into output: inout String, lines: [String]) {
    output += "BT\n"
    for line in centerLayout(lines: lines) {
      output += String(format: "/F1 %.2f Tf\n", line.fontSize)
      output += String(
        format: "1.0000 0.0000 0.0000 1.0000 %.2f %.2f Tm\n",
        line.origin.x, line.origin.y
      )
      output += "(\(line.text.map(escapePdfString).joined())) Tj\n"
    }
    output += "ET\n"
  }

  internal static func resolveStampTexts(locale: Locale) -> StampTexts {
    let language = locale.language.languageCode?.identifier.lowercased() ?? "en"
    let fiTitle = ["TARKASTA", "ASIAKIRJAN", "S\u{00C4}HK\u{00D6}INEN", "ALLEKIRJOITUS"]
    let svTitle = ["KONTROLLERA", "DOKUMENTETS", "ELEKTRONISKA", "SIGNATUR"]
    let enTitle = ["CHECK", "DOCUMENT", "ELECTRONIC", "SIGNATURE"]

    let fiBorder = "TARKASTA ASIAKIRJAN S\u{00C4}HK\u{00D6}INEN ALLEKIRJOITUS"
    let svBorder = "KONTROLLERA DOKUMENTETS ELEKTRONISKA SIGNATUR"
    let enBorder = "CHECK DOCUMENT ELECTRONIC SIGNATURE"

    switch language {
    case "sv":
      return StampTexts(
        middleLines: svTitle,
        topBorderText: fiBorder,
        bottomBorderText: enBorder
      )

    case "fi":
      return StampTexts(
        middleLines: fiTitle,
        topBorderText: svBorder,
        bottomBorderText: enBorder
      )

    default:
      return StampTexts(
        middleLines: enTitle,
        topBorderText: fiBorder,
        bottomBorderText: svBorder
      )
    }
  }

  private static func appendCircle(into output: inout String, radius: Double) {
    let controlOffset = radius * circleKappa
    output += String(format: "%.2f 0.00 m\n", radius)
    output += String(
      format: "%.2f %.2f %.2f %.2f 0.00 %.2f c\n",
      radius, controlOffset, controlOffset, radius, radius
    )
    output += String(
      format: "-%.2f %.2f -%.2f %.2f -%.2f 0.00 c\n",
      controlOffset, radius, radius, controlOffset, radius
    )
    output += String(
      format: "-%.2f -%.2f -%.2f -%.2f 0.00 -%.2f c\n",
      radius, controlOffset, controlOffset, radius, radius
    )
    output += String(
      format: "%.2f -%.2f %.2f -%.2f %.2f 0.00 c\n",
      controlOffset, radius, radius, controlOffset, radius
    )
  }

  private static func escapePdfString(_ character: Character) -> String {
    if let escaped = specialEscapes[character] {
      return escaped
    }
    guard let ascii = character.asciiValue else {
      if let scalar = character.unicodeScalars.first {
        return String(format: "\\%03o", Int(scalar.value) % octalByteModulus)
      }
      return String(character)
    }
    if ascii >= asciiPrintableMin, ascii <= asciiPrintableMax {
      return String(character)
    }
    return String(format: "\\%03o", ascii)
  }
}
