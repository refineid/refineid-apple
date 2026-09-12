// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineID

/// Where the visible mark lands, and the order the search gives ground
/// in.
///
/// The bottom-right corner is where a signature conventionally sits, so
/// that order is the whole design: it gives up size before it gives up
/// the corner, and gives up the corner before it climbs the page.
@Suite
internal struct StampSpotTests {
  /// A4 in points, the page every fixture here is built on.
  private static let pageWidth = 595.0
  private static let pageHeight = 842.0

  /// The mark's own reach, as the renderer builds it.
  private static let reach = 68.0

  /// How far from the page's edge a mark's centre may sit and still
  /// count as being in the corner.
  private static let cornerTolerance = 12.0

  /// The smallest the search may shrink a mark to.
  private static let smallestShare = 0.6

  /// The clear square left in the corner when the rest of the page is
  /// covered: too small for a full-size mark, big enough for a
  /// shrunken one.
  private static let clearCorner = 100.0

  /// One too deep for any size, and how far across the page it runs.
  private static let deepBand = 300.0
  private static let bandLeftEdge = 400.0

  /// Halves, for asking whether the mark stayed on the lower page.
  private static let halves = 2.0

  /// A pocket in the corner, wide enough only for a shrunken mark,
  /// walled off from the open page by a bar.
  private static let pocketLeftEdge = 490.0
  private static let pocketHeight = 95.0
  private static let barLeftEdge = 400.0
  private static let barWidth = 90.0

  /// A page carrying a content stream.
  private static func pageCarrying(_ content: String) -> Data {
    var text = "%PDF-1.7\n"
    var offsets: [Int] = []
    let bodies = [
      (1, "<< /Type /Catalog /Pages 2 0 R >>"),
      (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
      (
        3,
        "<< /Type /Page /Parent 2 0 R /MediaBox"
          + " [0 0 \(Self.pageWidth) \(Self.pageHeight)] /Contents 4 0 R >>"
      ),
    ]
    for (number, body) in bodies {
      offsets.append(text.utf8.count)
      text += "\(number) 0 obj\n\(body)\nendobj\n"
    }
    offsets.append(text.utf8.count)
    text += "4 0 obj\n<< /Length \(content.utf8.count) >>\nstream\n"
    text += "\(content)endstream\nendobj\n"
    let xrefOffset = text.utf8.count
    text += "xref\n0 5\n0000000000 65535 f \n"
    for offset in offsets {
      text += String(format: "%010d 00000 n \n", offset)
    }
    text += "trailer\n<< /Size 5 /Root 1 0 R >>\n"
    text += "startxref\n\(xrefOffset)\n%%EOF\n"
    return Data(text.utf8)
  }

  /// A filled rectangle, in the page's own coordinates.
  private static func ink(
    fromLeft left: Double,
    fromFoot foot: Double,
    width: Double,
    height: Double
  ) -> String {
    "0 0 0 rg \(left) \(foot) \(width) \(height) re f\n"
  }

  /// An empty page gives the mark the corner, at its full size.
  @Test
  internal func aBlankPageSeatsTheMarkInItsCornerAtFullSize() throws {
    let spot = try #require(
      StampSpot.free(inLastPageOf: Self.pageCarrying(""), reach: Self.reach)
    )
    #expect(spot.share == 1)
    #expect(abs(Self.pageWidth - spot.acrossPage - Self.reach) < Self.cornerTolerance)
    #expect(abs(spot.upPage - Self.reach) < Self.cornerTolerance)
  }

  /// A full-size mark further in beats a shrunken one in the corner.
  ///
  /// The corner holds a pocket only a small mark fits, and the open
  /// page beyond the bar holds room for a full-size one. Size is
  /// settled before place, so the mark leaves the corner rather than
  /// shrink to stay in it - the page has room, and a reader should
  /// get the larger mark.
  @Test
  internal func aFullSizeMarkFurtherInBeatsAShrunkenCorner() throws {
    var content = Self.ink(
      fromLeft: Self.barLeftEdge,
      fromFoot: 0,
      width: Self.barWidth,
      height: Self.pageHeight
    )
    content += Self.ink(
      fromLeft: Self.pocketLeftEdge,
      fromFoot: Self.pocketHeight,
      width: Self.pageWidth - Self.pocketLeftEdge,
      height: Self.pageHeight - Self.pocketHeight
    )
    let document = Self.pageCarrying(content)
    let spot = try #require(
      StampSpot.free(inLastPageOf: document, reach: Self.reach)
    )
    #expect(spot.share == 1)
    #expect(spot.acrossPage < Self.barLeftEdge)
  }

  /// A page with room for no full-size mark anywhere shrinks it rather
  /// than give up.
  ///
  /// Every part of the page is covered but a square in the corner, and
  /// that square is smaller than a full-size mark. Shrinking is the
  /// last thing given up, so it happens here and only here.
  @Test
  internal func aCrowdedCornerShrinksTheMarkBeforeMovingIt() throws {
    var content = Self.ink(
      fromLeft: 0,
      fromFoot: 0,
      width: Self.pageWidth - Self.clearCorner,
      height: Self.pageHeight
    )
    content += Self.ink(
      fromLeft: 0,
      fromFoot: Self.clearCorner,
      width: Self.pageWidth,
      height: Self.pageHeight - Self.clearCorner
    )
    let document = Self.pageCarrying(content)
    let spot = try #require(
      StampSpot.free(inLastPageOf: document, reach: Self.reach)
    )
    #expect(spot.share < 1)
    #expect(spot.share >= Self.smallestShare)
    // Still against the right edge: it gave up size, not the corner.
    let room = Self.reach * spot.share
    #expect(abs(Self.pageWidth - spot.acrossPage - room) < Self.cornerTolerance)
  }

  /// A caller may protect machine-readable detail by forbidding shrinkage.
  @Test
  internal func aFullSizeMinimumRefusesAShrinkOnlyPocket() {
    var content = Self.ink(
      fromLeft: 0,
      fromFoot: 0,
      width: Self.pageWidth - Self.clearCorner,
      height: Self.pageHeight
    )
    content += Self.ink(
      fromLeft: 0,
      fromFoot: Self.clearCorner,
      width: Self.pageWidth,
      height: Self.pageHeight - Self.clearCorner
    )

    #expect(
      StampSpot.free(
        inLastPageOf: Self.pageCarrying(content),
        reach: Self.reach,
        minimumShare: 1
      ) == nil
    )
  }

  /// Ink too deep to shrink under sends the mark left along the foot.
  @Test
  internal func anOccupiedCornerSendsTheMarkLeftBeforeUp() throws {
    let document = Self.pageCarrying(
      Self.ink(
        fromLeft: Self.bandLeftEdge,
        fromFoot: 0,
        width: Self.pageWidth - Self.bandLeftEdge,
        height: Self.deepBand
      )
    )
    let spot = try #require(
      StampSpot.free(inLastPageOf: document, reach: Self.reach)
    )
    #expect(spot.acrossPage < Self.bandLeftEdge)
    // It stayed low: moving left is cheaper than climbing.
    #expect(spot.upPage < Self.pageHeight / Self.halves)
  }

  /// A page with no clear space anywhere refuses rather than covering
  /// the document's own words.
  @Test
  internal func aFullPageRefusesTheMark() {
    let document = Self.pageCarrying(
      Self.ink(
        fromLeft: 0, fromFoot: 0, width: Self.pageWidth, height: Self.pageHeight
      )
    )
    #expect(StampSpot.free(inLastPageOf: document, reach: Self.reach) == nil)
  }
}
