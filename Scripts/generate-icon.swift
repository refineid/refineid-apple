// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// The RefineID app-icon source artwork, as code - SVG only.
//
// Design: an identity card and its gold chip, over the Finnish flag blue.
//
// Run: swift Scripts/generate-icon.swift <repo-root>
// Emits the Icon Composer document Sources/App/AppIcon.icon/ (icon.json
// plus the flat card and chip layers in Assets/). That bundle is the
// single icon artifact; actool compiles it into every appearance.
//
// Rules the output obeys:
//   - 1024 canvas: the App Store icon size and Icon Composer's point space
//     (icon.json translation-in-points lives there), so viewBox is 1:1.
//   - whole pixels only, and offsets rounded to tens where there is a choice.
//   - the chip engraving is written as centre +/- offset, so its halves are
//     exact mirrors and the figure is symmetric by construction.
//   - the SVG is pretty-printed and each feature carries an <!-- --> comment.

import Foundation

let canvas = 1024

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("usage: generate-icon.swift <repo-root>\n".utf8))
  exit(1)
}
let repoRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconBundle = repoRoot.appendingPathComponent("Sources/App/AppIcon.icon", isDirectory: true)
let iconAssets = iconBundle.appendingPathComponent("Assets", isDirectory: true)
// Recreate the assets directory so a retired layer can never linger.
try? FileManager.default.removeItem(at: iconAssets)
try! FileManager.default.createDirectory(at: iconAssets, withIntermediateDirectories: true)

// ---------------------------------------------------------------- palette
// Background: the law blue, applied as the .icon automatic-gradient fill
// (see icon.json, sRGB #134483). Valtioneuvoston päätös Suomen lipun
// väreistä (SDK 827/1993) defines the blue colorimetrically (§3, CIE
// D65, d/2°: Y 5.86, x 0.1856, y 0.1696) and itself calls PMS 294C only
// an approximation (§5) with a ΔE*ab ≤ 4 tolerance (§6). The primary xyY
// definition converts to sRGB #134483 (ΔE 3.4 to the decree's own Lab
// cross-definition - within its own tolerance).
//
// Flat layer fills (Liquid Glass: the system provides depth).
let flatCard = "#FFFFFF"
let flatChip = "#D9B96B"
let chipEngraveColor = "#77602F"
let chipEngraveWidth = 6

// ---------------------------------------------------------------- geometry
// All coordinates are y-up (drawn inside a flipped group) and whole pixels.
//
// Card: centred on the 1024 canvas.
let cardWidth = 700
let cardHeight = 440
let cardCornerRadius = 45
let cardX = (canvas - cardWidth) / 2   // 162
let cardY = (canvas - cardHeight) / 2  // 292

// Chip pad, upper-left on the card (Icon Composer nudges the whole chip
// layer toward the card centre by chipOffset* when it composes).
let chipWidth = 150
let chipHeight = 120
let chipCornerRadius = 35
let chipX = 240
let chipY = 520
let chipLeft = chipX                 // 240
let chipRight = chipX + chipWidth    // 390
let chipBottom = chipY               // 520  (y-up: the pad's lower edge)
let chipTop = chipY + chipHeight     // 640  (the pad's upper edge)
let cx = chipX + chipWidth / 2       // 315  the vertical mirror axis
let cy = chipY + chipHeight / 2      // 580  the horizontal mirror axis

// Engraving offsets from the centre (cx, cy). Everything is drawn as
// cx +/- <x-offset> and cy +/- <y-offset>, so both halves are identical.
let bandGap = 30      // the two horizontal band lines sit at cy +/- bandGap
let ringRadius = 30   // the central contact ring (touches both band lines)
let domeOuterX = 40   // a corner dome arc leaves its band line here
let domeCtrlX = 30    // the dome arc's quadratic control point
let domeInnerX = 10   // and the dome arc meets the card edge here
// Each index dot is centred in its band zone (between a band line at
// cy +/- bandGap and the card edge at cy +/- chipHeight/2), so this is
// derived, not rounded: (30 + 60) / 2 = 45, i.e. cy +/- 45.
let dotGap = (bandGap + chipHeight / 2) / 2
let dotRadius = 5

let bandTop = cy + bandGap       // 610
let bandBottom = cy - bandGap    // 550

let chipIconOffsetX = 35
let chipIconOffsetY = 75

// ---------------------------------------------------------------- helpers
func roundedRect(x: Int, y: Int, width: Int, height: Int, radius: Int, _ attributes: String) -> String {
  let tail = attributes.isEmpty ? "" : " " + attributes
  return "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(width)\" height=\"\(height)\" rx=\"\(radius)\"\(tail)/>"
}

func circle(cx: Int, cy: Int, radius: Int, fill: String) -> String {
  "<circle cx=\"\(cx)\" cy=\"\(cy)\" r=\"\(radius)\" fill=\"\(fill)\" stroke=\"none\"/>"
}

// Wraps pretty-printed, already-indented body lines in the SVG document and
// the y-up flip group.
func layer(_ body: [String]) -> String {
  var lines = ["<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(canvas) \(canvas)\">"]
  lines.append("<g transform=\"matrix(1,0,0,-1,0,\(canvas))\">")
  lines.append(contentsOf: body)
  lines.append("</g>")
  lines.append("</svg>")
  return lines.joined(separator: "\n") + "\n"
}

func write(_ content: String, to url: URL) {
  try! content.data(using: .utf8)!.write(to: url)
  print("wrote \(url.path)")
}

// ---------------------------------------------------------------- chip path
// The contact engraving as (comment, path) features. Each path holds the
// mirrored commands for one feature, so left=right and top=bottom, and each
// is emitted with an <!-- --> comment so the SVG explains itself.
let engravingFeatures: [(label: String, path: String)] = [
  (
    "two full-width horizontal band lines (top, bottom)",
    "M \(chipLeft) \(bandTop) H \(chipRight) M \(chipLeft) \(bandBottom) H \(chipRight)"
  ),
  (
    "central contact ring: two half-arcs back to the start point",
    "M \(cx - ringRadius) \(cy) A \(ringRadius) \(ringRadius) 0 1 0 \(cx + ringRadius) \(cy) "
      + "A \(ringRadius) \(ringRadius) 0 1 0 \(cx - ringRadius) \(cy)"
  ),
  (
    "short verticals joining each card edge to the ring (top, bottom)",
    "M \(cx) \(chipTop) V \(bandTop) M \(cx) \(bandBottom) V \(chipBottom)"
  ),
  (
    "four corner dome arcs, band line to card edge, mirrored on both axes",
    "M \(cx - domeOuterX) \(bandTop) Q \(cx - domeCtrlX) \(chipTop) \(cx - domeInnerX) \(chipTop) "
      + "M \(cx + domeOuterX) \(bandTop) Q \(cx + domeCtrlX) \(chipTop) \(cx + domeInnerX) \(chipTop) "
      + "M \(cx - domeOuterX) \(bandBottom) Q \(cx - domeCtrlX) \(chipBottom) \(cx - domeInnerX) \(chipBottom) "
      + "M \(cx + domeOuterX) \(bandBottom) Q \(cx + domeCtrlX) \(chipBottom) \(cx + domeInnerX) \(chipBottom)"
  ),
  (
    "mid contact lines from each card edge to the ring (left, right)",
    "M \(chipLeft) \(cy) H \(cx - ringRadius) M \(cx + ringRadius) \(cy) H \(chipRight)"
  ),
]

// ---------------------------------------------------------------- layers
write(
  layer([
    "\t<!-- the card body -->",
    "\t" + roundedRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight, radius: cardCornerRadius, "fill=\"\(flatCard)\""),
  ]),
  to: iconAssets.appendingPathComponent("layer-card.svg")
)

let chipPad = roundedRect(x: chipX, y: chipY, width: chipWidth, height: chipHeight, radius: chipCornerRadius, "")
var chipBody = [
  "\t<defs>",
  "\t\t<clipPath id=\"pad\">",
  "\t\t\t\(chipPad)",
  "\t\t</clipPath>",
  "\t</defs>",
  "\t<!-- gold contact pad -->",
  "\t" + roundedRect(x: chipX, y: chipY, width: chipWidth, height: chipHeight, radius: chipCornerRadius, "fill=\"\(flatChip)\""),
  "\t<g clip-path=\"url(#pad)\" fill=\"none\" stroke=\"\(chipEngraveColor)\" stroke-width=\"\(chipEngraveWidth)\">",
]
for feature in engravingFeatures {
  chipBody.append("\t\t<!-- \(feature.label) -->")
  chipBody.append("\t\t<path d=\"\(feature.path)\"/>")
}
chipBody.append("\t\t<!-- the pad edge, on top of the engraving -->")
chipBody.append("\t\t\(chipPad)")
chipBody.append("\t\t<!-- index dots, one centred in each band zone -->")
chipBody.append("\t\t" + circle(cx: cx, cy: cy + dotGap, radius: dotRadius, fill: chipEngraveColor))
chipBody.append("\t\t" + circle(cx: cx, cy: cy - dotGap, radius: dotRadius, fill: chipEngraveColor))
chipBody.append("\t</g>")
write(layer(chipBody), to: iconAssets.appendingPathComponent("layer-chip.svg"))

// ---------------------------------------------------------------- .icon
let iconJson = """
{
  "fill" : {
    "automatic-gradient" : "extended-srgb:0.07451,0.26667,0.51373,1.00000"
  },
  "groups" : [
    {
      "layers" : [
        {
          "glass" : true,
          "hidden" : false,
          "image-name" : "layer-chip.svg",
          "name" : "chip",
          "position" : {
            "scale" : 1,
            "translation-in-points" : [
              \(chipIconOffsetX),
              \(chipIconOffsetY)
            ]
          }
        },
        {
          "glass" : true,
          "hidden" : false,
          "image-name" : "layer-card.svg",
          "name" : "card"
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : 0.5
      },
      "translucency" : {
        "enabled" : true,
        "value" : 0.5
      }
    }
  ],
  "supported-platforms" : {
    "squares" : "shared"
  }
}
"""
// Byte-identical with Icon Composer's save: trim the multi-line
// template's trailing newline, which the canonical file lacks.
let canonicalJson = iconJson.hasSuffix("\n") ? String(iconJson.dropLast()) : iconJson
try! canonicalJson.data(using: .utf8)!.write(to: iconBundle.appendingPathComponent("icon.json"))
print("wrote \(iconBundle.appendingPathComponent("icon.json").path)")
print("wrote \(iconBundle.path)")
