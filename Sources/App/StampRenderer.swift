// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import CoreText
  import Foundation

  /// Draws the signature's visible mark: a ring carrying the identity
  /// the certificate states and, when available, the holder's own
  /// handwriting.
  ///
  /// Every part is vector. Nothing here is evidence - the signature is
  /// the evidence, and it is in the file - so the mark says what was
  /// signed and by whom, and claims nothing a reader could not check.
  internal enum StampRenderer {
    /// What the mark states.
    internal struct Statement {
      /// The holder as a person reads it.
      internal let name: String

      /// The identifier stated under it.
      internal let identifier: String

      /// The holder's traced handwriting, or nil when the card has none.
      internal let signature: SignatureArtwork.Artwork?
    }

    /// The ring.
    private static let outerRadius = 64.0
    private static let innerRadius = 57.0
    private static let outerLineWidth = 1.8
    private static let innerLineWidth = 0.9

    /// The signature's width inside the ring, and the baseline it
    /// stands on.
    private static let signatureWidth = 86.0
    private static let baselineHalfWidth = 45.0
    private static let baselineDrop = 6.0
    private static let signatureLift = 2.0
    private static let baselineWidth = 1.2

    /// Type sizes.
    private static let nameSize = 5.0

    /// How far the name sits below the line the signature stands on.
    private static let nameDrop = 13.0

    /// Clear space kept between the name's ends and the inner circle.
    private static let nameMargin = 16.0

    /// How far the identifier sits below the name.
    private static let nameLineGap = 8.0

    /// Identity-only stamps place two lines around the ring's centre.
    private static let identityNameLift = 5.0
    private static let identityIdentifierDrop = 10.0
    private static let identitySingleLineDrop = 4.0

    /// The identifier's size, as a share of the name's.
    private static let identifierShare = 0.85

    /// The largest the name may grow, so a short one does not become
    /// a headline inside a small ring.
    private static let nameCeiling = 11.0

    /// The circle's Bezier constant: how far a control point sits
    /// along the tangent to approximate a quarter turn.
    private static let arcControl = 0.5523

    /// Quarter turns in a circle.
    private static let quarterTurns = 4

    /// The fallback advance for a character the font has no glyph
    /// for, as a fraction of the type size.
    private static let fallbackAdvanceShare = 0.5

    /// Degrees in a half turn, for turning degrees into radians.
    private static let halfTurnDegrees = 180.0

    /// The size glyphs are measured at before scaling, large enough
    /// that hinting cannot round the answer.
    private static let metricSize = 1_000.0

    /// Two, for the halves a centred thing is placed by.
    private static let halves = 2.0

    /// A quarter turn, which both arcs measure their rotations from.
    private static let quarterTurn = Double.pi / Self.halves

    /// The mark's colour, #B02020, as the fractions PDF wants.
    private static let inkColour = "0.6902 0.1255 0.1255"

    /// How far the ring is turned, in degrees.
    ///
    /// A rubber stamp is never put down square, and one that lands at
    /// exactly the same angle every time looks like what it is: a
    /// drawing. The range starts well away from square, because a
    /// turn of a degree or two reads as a mistake rather than a hand.
    private static let leastTilt = 10.0
    private static let mostTilt = 20.0

    /// The page carrying the mark.
    internal static func mark(_ statement: Statement) -> StampMark {
      let centreX = 0.0
      let centreY = 0.0
      var body = "q\n"
      body += Self.tilt(about: (centreX, centreY))
      let centre = (horizontal: centreX, vertical: centreY)
      body += "\(Self.inkColour) RG \(Self.inkColour) rg\n"
      body += Self.circle(
        centre: centre, radius: Self.outerRadius, lineWidth: Self.outerLineWidth
      )
      body += Self.circle(
        centre: centre, radius: Self.innerRadius, lineWidth: Self.innerLineWidth
      )
      if let signature = statement.signature {
        body += Self.handwriting(signature, centre: (centreX, centreY))
        body += Self.identityBelowHandwriting(
          statement, centre: (centreX, centreY)
        )
      } else {
        body += Self.centredIdentity(statement, centre: (centreX, centreY))
      }
      body += "Q\nQ\n"
      return StampMark(radius: Self.outerRadius, operators: body)
    }

    /// One number, written the way PDF reads them.
    ///
    /// Swift writes a very small double as 3.9e-15, and PDF has no
    /// exponent notation - a reader meeting one either skips the
    /// operator or rejects the stream. Rounding sines and cosines of
    /// right angles to fixed places writes them as 0.0000, which is
    /// what they are.
    private static func number(_ value: Double) -> String {
      String(format: "%.4f", value)
    }

    /// A turn of up to `maximumTilt` degrees clockwise, about the
    /// ring's own centre, so no two stamps land at the same angle.
    private static func tilt(about centre: (horizontal: Double, vertical: Double)) -> String {
      let degrees = Double.random(in: Self.leastTilt...Self.mostTilt)
      let turn = -degrees * Double.pi / Self.halfTurnDegrees
      let cosine = cos(turn)
      let sine = sin(turn)
      let shiftX = centre.horizontal - centre.horizontal * cosine + centre.vertical * sine
      let shiftY = centre.vertical - centre.horizontal * sine - centre.vertical * cosine
      return "q \(Self.number(cosine)) \(Self.number(sine))"
        + " \(Self.number(-sine)) \(Self.number(cosine))"
        + " \(Self.number(shiftX)) \(Self.number(shiftY)) cm\n"
    }

    /// The holder's handwriting, fitted to the line it stands on.
    ///
    /// Scaled and placed by where the ink is, not by the card image's
    /// box: the box has blank margins around the writing, and placing
    /// it puts the margins on the line and the writing wherever they
    /// leave it. The writing starts where the line starts and ends
    /// before it does.
    private static func handwriting(
      _ artwork: SignatureArtwork.Artwork,
      centre: (horizontal: Double, vertical: Double)
    ) -> String {
      let inkWidth = artwork.inkRight - artwork.inkLeft
      guard inkWidth > 0 else { return "" }
      let room = Self.baselineHalfWidth * Self.halves
      let scale = room / inkWidth
      let left = centre.horizontal - Self.baselineHalfWidth
      let sits = centre.vertical - Self.baselineDrop + Self.signatureLift
      // The operators are in the image's own coordinates, so the
      // translation carries the ink's own corner to the line's end.
      var body = "q \(Self.number(scale)) 0 0 \(Self.number(scale))"
      body += " \(Self.number(left - artwork.inkLeft * scale))"
      body += " \(Self.number(sits - artwork.inkBottom * scale)) cm\n"
      body += artwork.operators
      body += "Q\n"
      body += "\(Self.number(Self.baselineWidth)) w "
      body +=
        "\(Self.number(centre.horizontal - Self.baselineHalfWidth))"
        + " \(Self.number(centre.vertical - Self.baselineDrop)) m "
      body +=
        "\(Self.number(centre.horizontal + Self.baselineHalfWidth))"
        + " \(Self.number(centre.vertical - Self.baselineDrop)) l S\n"
      return body
    }

    /// The name, on two lines: who, then the identifier.
    ///
    /// A common name on this card reads "SURNAME FORENAME" and then
    /// the identifier. On one line it reads like a database row and
    /// has to shrink to fit; on two it reads like a signature block,
    /// and each line is short enough to stay legible.
    private static func identityBelowHandwriting(
      _ statement: Statement,
      centre: (horizontal: Double, vertical: Double)
    ) -> String {
      var body = Self.line(
        statement.name,
        centre: centre,
        baseline: centre.vertical - Self.baselineDrop - Self.nameDrop,
        size: Self.nameSize,
        ceiling: Self.nameCeiling
      )
      guard !statement.identifier.isEmpty else { return body }
      body += Self.line(
        statement.identifier,
        centre: centre,
        baseline:
          centre.vertical - Self.baselineDrop - Self.nameDrop - Self.nameLineGap,
        size: Self.nameSize * Self.identifierShare,
        ceiling: Self.nameCeiling * Self.identifierShare
      )
      return body
    }

    /// The certificate name and SATU, centred when there is no handwriting.
    private static func centredIdentity(
      _ statement: Statement,
      centre: (horizontal: Double, vertical: Double)
    ) -> String {
      guard !statement.identifier.isEmpty else {
        return Self.line(
          statement.name,
          centre: centre,
          baseline: centre.vertical - Self.identitySingleLineDrop,
          size: Self.nameSize,
          ceiling: Self.nameCeiling
        )
      }
      return Self.line(
        statement.name,
        centre: centre,
        baseline: centre.vertical + Self.identityNameLift,
        size: Self.nameSize,
        ceiling: Self.nameCeiling
      )
        + Self.line(
          statement.identifier,
          centre: centre,
          baseline: centre.vertical - Self.identityIdentifierDrop,
          size: Self.nameSize * Self.identifierShare,
          ceiling: Self.nameCeiling * Self.identifierShare
        )
    }

    /// One line of the name, fitted to the ring's width at its own
    /// height.
    ///
    /// Fitted, not merely capped: a short name at a fixed size leaves
    /// the ring looking empty, and a long one had to shrink anyway.
    /// The size is taken from the room, both ways, and the chord
    /// narrows as a line sits lower - so each line is measured at its
    /// own height rather than sharing the one above.
    private static func line(
      _ text: String,
      centre: (horizontal: Double, vertical: Double),
      baseline: Double,
      size: Double,
      ceiling: Double
    ) -> String {
      let height = abs(baseline - centre.vertical)
      guard height < Self.innerRadius else { return "" }
      let halfChord =
        (Self.innerRadius * Self.innerRadius - height * height).squareRoot()
      let room = halfChord * Self.halves - Self.nameMargin
      let measured = TextOutline.line(text, font: "Helvetica", size: size)
      guard measured.width > 0 else { return "" }
      let chosen = min(size * room / measured.width, ceiling)
      let drawn = TextOutline.line(text, font: "Helvetica", size: chosen)
      // On the ring's own axis: both lines centred under the writing,
      // which is what makes a round stamp look round.
      return "q 1 0 0 1 \(Self.number(centre.horizontal)) \(Self.number(baseline)) cm\n"
        + "\(drawn.operators)Q\n"
    }

    /// A circle, as four Bezier quarters.
    ///
    /// Each quarter's control points sit along the tangents at its
    /// ends, which is what makes four curves indistinguishable from a
    /// circle at any zoom.
    private static func circle(
      centre: (horizontal: Double, vertical: Double),
      radius: Double,
      lineWidth: Double
    ) -> String {
      let pull = Self.arcControl * radius
      var body = "\(Self.number(lineWidth)) w\n"
      body += "\(Self.number(centre.horizontal + radius)) \(Self.number(centre.vertical)) m\n"
      for quarter in 0..<Self.quarterTurns {
        let opens = Double(quarter) * Self.quarterTurn
        let closes = opens + Self.quarterTurn
        let start = (
          horizontal: centre.horizontal + radius * cos(opens),
          vertical: centre.vertical + radius * sin(opens)
        )
        let end = (
          horizontal: centre.horizontal + radius * cos(closes),
          vertical: centre.vertical + radius * sin(closes)
        )
        let leaving = (
          horizontal: start.horizontal - pull * sin(opens),
          vertical: start.vertical + pull * cos(opens)
        )
        let arriving = (
          horizontal: end.horizontal + pull * sin(closes),
          vertical: end.vertical - pull * cos(closes)
        )
        body +=
          "\(Self.number(leaving.horizontal)) \(Self.number(leaving.vertical))"
          + " \(Self.number(arriving.horizontal)) \(Self.number(arriving.vertical))"
          + " \(Self.number(end.horizontal)) \(Self.number(end.vertical)) c\n"
      }
      return body + "h\nS\n"
    }
  }

#endif
