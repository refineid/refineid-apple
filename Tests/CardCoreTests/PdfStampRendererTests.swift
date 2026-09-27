// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

@Suite
internal struct PdfStampRendererTests {
  @Test
  internal func stampMarkProducesExpectedGeometry() {
    let mark = PdfStampRenderer.stampMark(locale: Locale(identifier: "en_US"))
    #expect(mark.radius == 64.0)
    #expect(mark.reach == 68.0)
    #expect(!mark.operators.isEmpty)
    #expect(mark.operators.contains("0.7765 0.1569 0.1569 RG"))
  }

  @Test
  internal func localizedTextsMatchLanguages() {
    let fiTexts = PdfStampRenderer.resolveStampTexts(locale: Locale(identifier: "fi_FI"))
    #expect(
      fiTexts.middleLines == ["TARKASTA", "ASIAKIRJAN", "S\u{00C4}HK\u{00D6}INEN", "ALLEKIRJOITUS"])
    #expect(fiTexts.bottomBorderText == "CHECK DOCUMENT ELECTRONIC SIGNATURE")

    let svTexts = PdfStampRenderer.resolveStampTexts(locale: Locale(identifier: "sv_SE"))
    #expect(svTexts.middleLines == ["KONTROLLERA", "DOKUMENTETS", "ELEKTRONISKA", "SIGNATUR"])
    #expect(svTexts.bottomBorderText == "CHECK DOCUMENT ELECTRONIC SIGNATURE")

    let enTexts = PdfStampRenderer.resolveStampTexts(locale: Locale(identifier: "en_US"))
    #expect(enTexts.middleLines == ["CHECK", "DOCUMENT", "ELECTRONIC", "SIGNATURE"])
    #expect(enTexts.bottomBorderText == "KONTROLLERA DOKUMENTETS ELEKTRONISKA SIGNATUR")
  }

  @Test
  internal func generatedOperatorsContainFontsAndCenterText() {
    let operators = PdfStampRenderer.generateStampOperators(locale: Locale(identifier: "fi_FI"))
    #expect(operators.contains("/F1"))
    #expect(operators.contains("Tj"))
    #expect(operators.hasPrefix("q\n"))
    #expect(operators.hasSuffix("Q\n"))
  }

  @Test(arguments: ["en_US", "fi_FI", "sv_SE"])
  internal func centerInkIsCenteredAndClearsCircle(localeIdentifier: String) {
    let texts = PdfStampRenderer.resolveStampTexts(locale: Locale(identifier: localeIdentifier))
    let layout = PdfStampRenderer.centerLayout(lines: texts.middleLines)
    let inkBounds = layout.reduce(CGRect.null) { bounds, line in
      let ink = line.bounds.offsetBy(dx: line.origin.x, dy: line.origin.y)
      #expect(abs(ink.midX) < 0.001)
      for pointX in [ink.minX, ink.maxX] {
        for pointY in [ink.minY, ink.maxY] {
          #expect(hypot(pointX, pointY) < 46.0)
        }
      }
      #expect(line.fontSize >= 8.0)
      return bounds.union(ink)
    }
    #expect(abs(inkBounds.midY) < 0.001)
    #expect(layout.count == 4)
    #expect(Set(layout.map(\.fontSize)).count == 1)
  }

  @Test
  internal func ringsAndArcTypographyHaveExpectedGeometry() {
    let operators = PdfStampRenderer.generateStampOperators(locale: Locale(identifier: "en_US"))
    #expect(operators.components(separatedBy: "\nS\n").count - 1 == 2)
    #expect(!operators.contains("45.00 0.00 m"))
    #expect(operators.components(separatedBy: "/F1 4.80 Tf").count - 1 == 2)
    #expect(operators.components(separatedBy: "BT\n").count - 1 == 3)
    #expect(operators.components(separatedBy: "ET\n").count - 1 == 3)
  }

  @Test(arguments: [5.0, 10.0, 15.0])
  internal func completeStampRotatesCounterclockwiseWithoutChangingReach(degrees: Double) throws {
    let mark = PdfStampRenderer.stampMark(
      locale: Locale(identifier: "sv_SE"), rotationDegrees: degrees)
    let matrixLine = try #require(mark.operators.split(separator: "\n").dropFirst().first)
    let values = matrixLine.split(separator: " ").prefix(6).compactMap { Double($0) }
    #expect(values.count == 6)
    let radians = degrees * Double.pi / 180.0
    #expect(abs(values[0] - cos(radians)) < 0.00000001)
    #expect(abs(values[1] - sin(radians)) < 0.00000001)
    #expect(values[1] > 0)
    #expect(values[2] == -values[1])
    #expect(values[3] == values[0])
    #expect(values[4] == 0 && values[5] == 0)
    #expect(abs(hypot(values[0], values[1]) - 1) < 0.00000001)
    #expect(mark.radius == 64.0 && mark.reach == 68.0)
    #expect(mark.operators.hasPrefix("q\n"))
    #expect(mark.operators.hasSuffix("Q\n"))
  }

  @Test
  internal func newlyCreatedStampChoosesAngleInReadableRange() throws {
    let mark = PdfStampRenderer.stampMark(locale: Locale(identifier: "en_US"))
    let matrixLine = try #require(mark.operators.split(separator: "\n").dropFirst().first)
    let values = matrixLine.split(separator: " ").prefix(2).compactMap { Double($0) }
    let degrees = atan2(values[1], values[0]) * 180.0 / Double.pi
    #expect(degrees >= 4.999999 && degrees <= 15.000001)
  }

}
