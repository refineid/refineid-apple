#!/usr/bin/env swift  // Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// Generate RefineID Slack Workspace Icons matching official Slack Guidelines:
//   - Canvas: Exactly 4000 x 4000 pixels (Slack maximum high-resolution asset)
//   - Background: Solid statutory Finnish flag blue (sRGB #134483, SDK 827/1993)
//     (Full-bleed square canvas, allowing Slack's squircle mask to crop cleanly)
//   - Graphical logo: Pure white FINEID card with soft elevation drop shadow,
//     centered with comfortable padding (~15.8% horizontal, ~28.5% vertical)
//   - Gold contact chip (#D9B96B) with statutory circuit engraving (#77602F)
//   - Output format: PNG (< 10 MB limit) and SVG source vector
//
// Usage:
//   swift Scripts/generate-slack-icon.swift [output-directory]

import Cocoa
import CoreGraphics
import Foundation

let canvasSize: CGFloat = 4000.0

// Color Palette
// Finnish Law Blue sRGB #134483 per Valtioneuvoston päätös Suomen lipun väreistä (SDK 827/1993)
let lawBlueHex = "#134483"
let lawBlueRGB: (CGFloat, CGFloat, CGFloat) = (19.0 / 255.0, 68.0 / 255.0, 131.0 / 255.0)
let topGradientRGB: (CGFloat, CGFloat, CGFloat) = (31.0 / 255.0, 90.0 / 255.0, 166.0 / 255.0)  // #1F5AA6
let botGradientRGB: (CGFloat, CGFloat, CGFloat) = (16.0 / 255.0, 60.0 / 255.0, 118.0 / 255.0)  // #103C76

let cardFillHex = "#FFFFFF"
let chipBaseHex = "#D9B96B"
let chipEngraveHex = "#77602F"

// Proportions derived from master 1024 vector canvas:
// Card: 700 x 440, corner radius 45, centered on canvas
let cardScaleRatio: CGFloat = 700.0 / 1024.0  // ~0.68359375
let cardWidth = canvasSize * cardScaleRatio  // 2734.375
let cardHeight = cardWidth * (440.0 / 700.0)  // 1718.75
let cardRadius = cardHeight * (45.0 / 440.0)  // 175.78125

let cardX = (canvasSize - cardWidth) / 2.0  // 632.8125
let cardY = (canvasSize - cardHeight) / 2.0  // 1140.625
let cardRect = CGRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)

// Chip: 150 x 120, corner radius 35, on left side of card
let chipWidth = cardWidth * (150.0 / 700.0)  // 585.9375
let chipHeight = cardHeight * (120.0 / 440.0)  // 468.75
let chipRadius = chipHeight * (35.0 / 120.0)  // 136.71875

// Horizontal offset from card center: -23.14% of cardWidth
let chipCx = cardRect.midX - cardWidth * 0.23142857  // 1367.1875
let chipCy = cardRect.midY  // vertically centered on card
let chipRect = CGRect(
  x: chipCx - chipWidth / 2.0,
  y: chipCy - chipHeight / 2.0,
  width: chipWidth,
  height: chipHeight
)

/// sRGB colour space every colour and the canvas use.
let colorSpace: CGColorSpace = {
  guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
    fatalError("sRGB colour space unavailable")
  }
  return space
}()

/// One sRGB colour from components in 0...1.
func srgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat) -> CGColor {
  CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

/// A gradient over sRGB colours at the given locations.
func makeGradient(colors: CFArray, locations: [CGFloat]) -> CGGradient {
  guard let made = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else {
    fatalError("gradient not created")
  }
  return made
}

func renderSlackIconPNG(isGradient: Bool) -> Data {
  guard
    let ctx = CGContext(
      data: nil,
      width: Int(canvasSize),
      height: Int(canvasSize),
      bitsPerComponent: 8,
      bytesPerRow: Int(canvasSize) * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else {
    fatalError("Failed to create CGContext")
  }

  ctx.setShouldAntialias(true)
  ctx.setAllowsAntialiasing(true)
  ctx.interpolationQuality = .high

  // 1. Full-bleed background
  let fullRect = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
  if isGradient {
    let topColor = srgb(topGradientRGB.0, topGradientRGB.1, topGradientRGB.2, 1.0)
    let botColor = srgb(botGradientRGB.0, botGradientRGB.1, botGradientRGB.2, 1.0)
    let colors = [topColor, botColor] as CFArray
    let gradient = makeGradient(colors: colors, locations: [0.0, 1.0])
    ctx.drawLinearGradient(
      gradient, start: CGPoint(x: 0, y: canvasSize), end: CGPoint(x: 0, y: 0), options: [])
  } else {
    let lawBlue = srgb(lawBlueRGB.0, lawBlueRGB.1, lawBlueRGB.2, 1.0)
    ctx.setFillColor(lawBlue)
    ctx.fill(fullRect)
  }

  // 2. Card Drop Shadow
  ctx.saveGState()
  let shadowColor = srgb(0.0, 0.05, 0.15, 0.38)
  let shadowBlur = canvasSize * 0.035  // 140px blur
  let shadowOffset = CGSize(width: 0, height: -canvasSize * 0.015)  // downward offset in CG
  ctx.setShadow(offset: shadowOffset, blur: shadowBlur, color: shadowColor)

  let cardPath = CGPath(
    roundedRect: cardRect, cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil)
  ctx.addPath(cardPath)
  ctx.setFillColor(srgb(1.0, 1.0, 1.0, 1.0))
  ctx.fillPath()
  ctx.restoreGState()

  // 3. Card Surface (Liquid Glass subtle shading and top rim highlight)
  ctx.saveGState()
  ctx.addPath(cardPath)
  ctx.clip()

  let cardTop = srgb(1.0, 1.0, 1.0, 1.0)
  let cardMid = srgb(0.97, 0.98, 0.99, 1.0)
  let cardBot = srgb(0.91, 0.94, 0.97, 1.0)
  let cardGradColors = [cardTop, cardMid, cardBot] as CFArray
  let cardGradLocs: [CGFloat] = [0.0, 0.6, 1.0]
  let cardGradient = makeGradient(colors: cardGradColors, locations: cardGradLocs)
  ctx.drawLinearGradient(
    cardGradient,
    start: CGPoint(x: cardRect.midX, y: cardRect.maxY),
    end: CGPoint(x: cardRect.midX, y: cardRect.minY),
    options: []
  )

  // Specular top highlight
  let edgePath = CGPath(
    roundedRect: cardRect.insetBy(dx: 1, dy: 1),
    cornerWidth: cardRadius - 1,
    cornerHeight: cardRadius - 1,
    transform: nil
  )
  ctx.addPath(edgePath)
  ctx.setStrokeColor(srgb(1.0, 1.0, 1.0, 0.75))
  ctx.setLineWidth(canvasSize * 0.0015)
  ctx.strokePath()
  ctx.restoreGState()

  // 4. Chip Pad Elevation & Base
  let chipBaseColor = srgb(217.0 / 255.0, 185.0 / 255.0, 107.0 / 255.0, 1.0)  // #D9B96B
  let chipEngraveColor = srgb(119.0 / 255.0, 96.0 / 255.0, 47.0 / 255.0, 1.0)  // #77602F

  let chipPath = CGPath(
    roundedRect: chipRect, cornerWidth: chipRadius, cornerHeight: chipRadius, transform: nil)

  ctx.saveGState()
  let chipShadow = srgb(0.1, 0.15, 0.2, 0.18)
  ctx.setShadow(
    offset: CGSize(width: 0, height: -canvasSize * 0.003), blur: canvasSize * 0.006,
    color: chipShadow)
  ctx.addPath(chipPath)
  ctx.setFillColor(chipBaseColor)
  ctx.fillPath()
  ctx.restoreGState()

  // 5. Chip Pad Surface & Engravings
  ctx.saveGState()
  ctx.addPath(chipPath)
  ctx.clip()

  // Metallic gradient on pad
  let goldTop = srgb(224.0 / 255.0, 196.0 / 255.0, 122.0 / 255.0, 1.0)
  let goldBot = srgb(205.0 / 255.0, 172.0 / 255.0, 96.0 / 255.0, 1.0)
  let goldGradient = makeGradient(colors: [goldTop, goldBot] as CFArray, locations: [0.0, 1.0])
  ctx.drawLinearGradient(
    goldGradient, start: CGPoint(x: chipCx, y: chipRect.maxY),
    end: CGPoint(x: chipCx, y: chipRect.minY), options: [])

  // Engraving dimensions
  let bandGap = chipHeight * (30.0 / 120.0)
  let ringRadius = chipHeight * (30.0 / 120.0)
  let domeOuterX = chipWidth * (40.0 / 150.0)
  let domeCtrlX = chipWidth * (30.0 / 150.0)
  let domeInnerX = chipWidth * (10.0 / 150.0)
  let dotGap = chipHeight * (45.0 / 120.0)
  let dotRadius = chipHeight * (5.0 / 120.0)
  let engraveWidth = chipHeight * (6.0 / 120.0)

  let bandTop = chipCy + bandGap
  let bandBottom = chipCy - bandGap

  ctx.setStrokeColor(chipEngraveColor)
  ctx.setLineWidth(engraveWidth)
  ctx.setLineCap(.round)
  ctx.setLineJoin(.round)

  // Horizontal bands
  ctx.move(to: CGPoint(x: chipRect.minX, y: bandTop))
  ctx.addLine(to: CGPoint(x: chipRect.maxX, y: bandTop))
  ctx.move(to: CGPoint(x: chipRect.minX, y: bandBottom))
  ctx.addLine(to: CGPoint(x: chipRect.maxX, y: bandBottom))
  ctx.strokePath()

  // Central contact ring
  let ringRect = CGRect(
    x: chipCx - ringRadius, y: chipCy - ringRadius, width: ringRadius * 2, height: ringRadius * 2)
  ctx.addEllipse(in: ringRect)
  ctx.strokePath()

  // Verticals
  ctx.move(to: CGPoint(x: chipCx, y: chipRect.maxY))
  ctx.addLine(to: CGPoint(x: chipCx, y: bandTop))
  ctx.move(to: CGPoint(x: chipCx, y: bandBottom))
  ctx.addLine(to: CGPoint(x: chipCx, y: chipRect.minY))
  ctx.strokePath()

  // Corner dome arcs (quadratic Bézier curves)
  ctx.move(to: CGPoint(x: chipCx - domeOuterX, y: bandTop))
  ctx.addQuadCurve(
    to: CGPoint(x: chipCx - domeInnerX, y: chipRect.maxY),
    control: CGPoint(x: chipCx - domeCtrlX, y: chipRect.maxY))
  ctx.move(to: CGPoint(x: chipCx + domeOuterX, y: bandTop))
  ctx.addQuadCurve(
    to: CGPoint(x: chipCx + domeInnerX, y: chipRect.maxY),
    control: CGPoint(x: chipCx + domeCtrlX, y: chipRect.maxY))
  ctx.move(to: CGPoint(x: chipCx - domeOuterX, y: bandBottom))
  ctx.addQuadCurve(
    to: CGPoint(x: chipCx - domeInnerX, y: chipRect.minY),
    control: CGPoint(x: chipCx - domeCtrlX, y: chipRect.minY))
  ctx.move(to: CGPoint(x: chipCx + domeOuterX, y: bandBottom))
  ctx.addQuadCurve(
    to: CGPoint(x: chipCx + domeInnerX, y: chipRect.minY),
    control: CGPoint(x: chipCx + domeCtrlX, y: chipRect.minY))
  ctx.strokePath()

  // Mid contact lines
  ctx.move(to: CGPoint(x: chipRect.minX, y: chipCy))
  ctx.addLine(to: CGPoint(x: chipCx - ringRadius, y: chipCy))
  ctx.move(to: CGPoint(x: chipCx + ringRadius, y: chipCy))
  ctx.addLine(to: CGPoint(x: chipRect.maxX, y: chipCy))
  ctx.strokePath()

  // Index dots
  ctx.setFillColor(chipEngraveColor)
  ctx.fillEllipse(
    in: CGRect(
      x: chipCx - dotRadius, y: chipCy + dotGap - dotRadius, width: dotRadius * 2,
      height: dotRadius * 2))
  ctx.fillEllipse(
    in: CGRect(
      x: chipCx - dotRadius, y: chipCy - dotGap - dotRadius, width: dotRadius * 2,
      height: dotRadius * 2))

  // Pad rim stroke
  ctx.addPath(chipPath)
  ctx.setStrokeColor(chipEngraveColor)
  ctx.setLineWidth(engraveWidth)
  ctx.strokePath()

  ctx.restoreGState()

  guard let image = ctx.makeImage() else {
    fatalError("Failed to create CGImage")
  }

  let bitmapRep = NSBitmapImageRep(cgImage: image)
  guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to convert image to PNG")
  }
  return pngData
}

func generateSlackIconSVG(isGradient: Bool) -> String {
  let bgFill = isGradient ? "url(#field)" : lawBlueHex
  let gradientDef = """
      <defs>
        <linearGradient id="field" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#1f5aa6"/>
          <stop offset="1" stop-color="#103c76"/>
        </linearGradient>
        <filter id="card-shadow" x="-10%" y="-10%" width="130%" height="130%">
          <feDropShadow dx="0" dy="60" stdDeviation="80" flood-color="#000d26" flood-opacity="0.38"/>
        </filter>
        <clipPath id="pad">
          <rect x="240" y="520" width="150" height="120" rx="35"/>
        </clipPath>
      </defs>
    """

  return """
    <?xml version="1.0" encoding="UTF-8"?>
    <!--
      Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
      RefineID Slack Workspace Icon (4000x4000 viewBox).
    -->
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="4000" height="4000">
    \(gradientDef)
      <!-- Full-bleed background for Slack squircle cropping -->
      <rect x="0" y="0" width="1024" height="1024" fill="\(bgFill)"/>

      <!-- Centered RefineID identity card with soft elevation shadow -->
      <rect x="162" y="292" width="700" height="440" rx="45" fill="#FFFFFF" filter="url(#card-shadow)"/>

      <!-- Gold contact chip on left side of card -->
      <g transform="translate(35,75)">
        <g transform="matrix(1,0,0,-1,0,1024)">
          <!-- Gold contact pad -->
          <rect x="240" y="520" width="150" height="120" rx="35" fill="\(chipBaseHex)"/>
          <g clip-path="url(#pad)" fill="none" stroke="\(chipEngraveHex)" stroke-width="6">
            <!-- Two horizontal band lines -->
            <path d="M 240 610 H 390 M 240 550 H 390"/>
            <!-- Central contact ring -->
            <path d="M 285 580 A 30 30 0 1 0 345 580 A 30 30 0 1 0 285 580"/>
            <!-- Short verticals joining card edge to ring -->
            <path d="M 315 640 V 610 M 315 550 V 520"/>
            <!-- Four corner dome arcs -->
            <path d="M 275 610 Q 285 640 305 640 M 355 610 Q 345 640 325 640 M 275 550 Q 285 520 305 520 M 355 550 Q 345 520 325 520"/>
            <!-- Mid contact lines -->
            <path d="M 240 580 H 285 M 345 580 H 390"/>
            <!-- Pad rim stroke -->
            <rect x="240" y="520" width="150" height="120" rx="35"/>
            <!-- Contact index dots -->
            <circle cx="315" cy="625" r="5" fill="\(chipEngraveHex)" stroke="none"/>
            <circle cx="315" cy="535" r="5" fill="\(chipEngraveHex)" stroke="none"/>
          </g>
        </g>
      </g>
    </svg>
    """
}

// Destination directories
let repoRoot = URL(
  fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".",
  isDirectory: true)
let slackMetadataDir = repoRoot.appendingPathComponent("Metadata/slack", isDirectory: true)
try? FileManager.default.createDirectory(at: slackMetadataDir, withIntermediateDirectories: true)

// 1. Primary Slack Icon (Solid Law Blue #134483)
let solidPNGData = renderSlackIconPNG(isGradient: false)
let solidPNGURL = slackMetadataDir.appendingPathComponent("slack-icon-4000x4000.png")
try solidPNGData.write(to: solidPNGURL)
print(
  "Wrote \(solidPNGURL.path) (\(String(format: "%.2f", Double(solidPNGData.count) / 1_048_576.0)) MB)"
)

// 2. Variant Slack Icon (Subtle Gradient)
let gradientPNGData = renderSlackIconPNG(isGradient: true)
let gradientPNGURL = slackMetadataDir.appendingPathComponent("slack-icon-gradient-4000x4000.png")
try gradientPNGData.write(to: gradientPNGURL)
print(
  "Wrote \(gradientPNGURL.path) (\(String(format: "%.2f", Double(gradientPNGData.count) / 1_048_576.0)) MB)"
)

// 3. SVG vector source
let svgContent = generateSlackIconSVG(isGradient: false)
let svgURL = slackMetadataDir.appendingPathComponent("slack-icon.svg")
try Data(svgContent.utf8).write(to: svgURL)
print("Wrote \(svgURL.path)")
