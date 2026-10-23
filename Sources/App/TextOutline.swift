// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CoreGraphics
  import CoreText
  import Foundation

  /// Turns a line of text into PDF path operators.
  ///
  /// The stamp draws no text, only shapes. A page's font resources
  /// belong to the document, not to a mark laid over it, and every
  /// font-shaped thing on this stamp has gone wrong at least once:
  /// accents written in one encoding and read in another, advances
  /// measured at a size where they come back rounded, a font name a
  /// page might already mean something else by. Outlines have none of
  /// those failure modes and render identically in every reader.
  ///
  /// What is given up is selectable, searchable text. For a mark that
  /// is a picture of a rubber stamp, that is the right side of the
  /// trade.
  internal enum TextOutline {
    /// A traced line: its operators, centred on the origin, and how
    /// wide it came out.
    internal struct Line {
      /// Operators filling the glyphs.
      internal let operators: String

      /// The line's width at the requested size.
      internal let width: Double
    }

    /// The size glyphs are measured and traced at, large enough that
    /// hinting cannot round the answer; the caller scales down.
    private static let traceSize = 1_000.0

    /// Places kept after the decimal point in a coordinate.
    ///
    /// The glyphs are traced in a thousand-unit space, so hundredths
    /// of a unit are already finer than any reader draws.
    private static let decimals = 2

    /// Places kept in a scale factor.
    ///
    /// A scale is a small number where a coordinate is a large one:
    /// text at four points in that thousand-unit space scales by
    /// 0.004, which two places round to zero - and the line is drawn
    /// at no size at all, present in the file and invisible on the
    /// page.
    private static let scaleDecimals = 6

    /// Halves, for centring a line on the origin.
    private static let halves = 2.0

    /// Where a curve's points sit in the element it belongs to.
    private static let firstPoint = 0
    private static let secondPoint = 1
    private static let thirdPoint = 2

    /// Traces one line, centred horizontally on the origin and
    /// sitting on it.
    internal static func line(
      _ text: String,
      font: String,
      size: Double
    ) -> Line {
      let traced = CTFontCreateWithName(font as CFString, Self.traceSize, nil)
      let scale = size / Self.traceSize
      var body = ""
      var pen = 0.0
      var leftmost = Double.greatestFiniteMagnitude
      var rightmost = -Double.greatestFiniteMagnitude
      for character in text {
        // One glyph slot per code unit. A character outside the basic
        // plane is two units, and CoreText writes one glyph per unit -
        // told the length while given room for one, it writes past the
        // end.
        var codeUnits = Array(String(character).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: codeUnits.count)
        guard
          CTFontGetGlyphsForCharacters(
            traced, &codeUnits, &glyphs, codeUnits.count
          ),
          var glyph = glyphs.first
        else {
          continue
        }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(traced, .horizontal, &glyph, &advance, 1)
        if let path = CTFontCreatePathForGlyph(traced, glyph, nil) {
          body += Self.operators(of: path, offsetBy: pen)
          let box = path.boundingBoxOfPath
          leftmost = min(leftmost, Double(box.minX) + pen)
          rightmost = max(rightmost, Double(box.maxX) + pen)
        }
        pen += Double(advance.width)
      }
      // Measured from the glyph outlines rather than from the sum of
      // their advances. The two disagreed - by half - and it is the
      // outlines a reader draws, so a line centred and sized by the
      // advances ran off the ring it was fitted to.
      guard leftmost <= rightmost else {
        return Line(operators: "", width: 0)
      }
      let inkWidth = (rightmost - leftmost) * scale
      // Centred on the origin by its ink, not by its advances: a
      // round stamp reads as a stamp when what is inside it shares
      // the ring's axis.
      let centring = -(leftmost + rightmost) / Self.halves * scale
      let factor = String(format: "%.\(Self.scaleDecimals)f", scale)
      let placed =
        "q \(factor) 0 0 \(factor)"
        + " \(Self.number(centring)) 0 cm\n\(body)Q\n"
      return Line(operators: placed, width: inkWidth)
    }

    /// One glyph's path as operators, shifted along the line.
    private static func operators(of path: CGPath, offsetBy pen: Double) -> String {
      var body = ""
      path.applyWithBlock { element in
        let points = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint:
          body += "\(Self.at(points[Self.firstPoint], pen)) m\n"

        case .addLineToPoint:
          body += "\(Self.at(points[Self.firstPoint], pen)) l\n"

        case .addQuadCurveToPoint:
          body +=
            "\(Self.at(points[Self.firstPoint], pen)) \(Self.at(points[Self.secondPoint], pen)) v\n"

        case .addCurveToPoint:
          body +=
            "\(Self.at(points[Self.firstPoint], pen)) \(Self.at(points[Self.secondPoint], pen))"
            + " \(Self.at(points[Self.thirdPoint], pen)) c\n"

        case .closeSubpath:
          body += "h\n"

        @unknown default:
          break
        }
      }
      return body.isEmpty ? "" : body + "f\n"
    }

    /// One number, written the way PDF reads them: no exponents.
    private static func number(_ value: Double) -> String {
      String(format: "%.\(Self.decimals)f", value)
    }

    /// One point, shifted and rounded.
    private static func at(_ point: CGPoint, _ pen: Double) -> String {
      String(
        format: "%.\(Self.decimals)f %.\(Self.decimals)f",
        Double(point.x) + pen,
        Double(point.y)
      )
    }
  }

#endif
