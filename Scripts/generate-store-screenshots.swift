#!/usr/bin/env swift
// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// Generate App Store marketing screenshots for RefineID macOS and iOS.
//
// Composes marketing screenshots with zero alpha channel,
// matching Apple App Store Connect specifications and legal standards:
//   - macOS (APP_DESKTOP): 2880x1800 (16:10)
//   - iOS (APP_IPHONE_67): 1290x2796 (iPhone 6.7"/6.9")
//   - iPadOS (APP_IPAD_PRO_3GEN_129): 2048x2732 (iPad Pro 12.9"/13")
//
// Uses official Golden Gate dark wallpaper and native UI captures for each locale.
//
// Usage:
//   swift Scripts/generate-store-screenshots.swift [--platform <macos|ios|ipad|all>] [--locale <fi|en-US|sv|all>]

import Cocoa

struct SlideData {
    let filename: String
    let title: String
    let subtitle: String
    let assetName: String
}

let macosCatalog: [String: [SlideData]] = [
    "fi": [
        SlideData(
            filename: "01-authentication.png",
            title: "Tunnistaudu henkilökortilla verkkopalveluihin",
            subtitle: "Voit käyttää myös puhelinta langattomana kortinlukijana.",
            assetName: "window-card-fi.png"
        ),
        SlideData(
            filename: "02-documents.png",
            title: "Allekirjoita asiakirjoja",
            subtitle: "Luo ja tarkasta hyväksyttyjä sähköisiä allekirjoituksia.",
            assetName: "window-documents-fi.png"
        )
    ],
    "en-US": [
        SlideData(
            filename: "01-authentication.png",
            title: "Log in to web services with your identity card",
            subtitle: "You can also use your phone as a wireless card reader.",
            assetName: "window-card-en.png"
        ),
        SlideData(
            filename: "02-documents.png",
            title: "Sign documents",
            subtitle: "Create and verify qualified electronic signatures.",
            assetName: "window-documents-en.png"
        )
    ],
    "sv": [
        SlideData(
            filename: "01-authentication.png",
            title: "Identifiera dig till e-tjänster med identitetskort",
            subtitle: "Du kan även använda telefonen som trådlös kortläsare.",
            assetName: "window-card-sv.png"
        ),
        SlideData(
            filename: "02-documents.png",
            title: "Underteckna dokument",
            subtitle: "Skapa och granska kvalificerade elektroniska underskrifter.",
            assetName: "window-documents-sv.png"
        )
    ]
]

let iosCatalog: [String: [SlideData]] = [
    "fi": [
        SlideData(
            filename: "01-app-main.png",
            title: "Tunnistaudu henkilökortilla verkkopalveluihin",
            subtitle: "Voit käyttää myös puhelinta langattomana kortinlukijana.",
            assetName: "iphone-main-fi.png"
        ),
        SlideData(
            filename: "02-documents.png",
            title: "Allekirjoita asiakirjoja",
            subtitle: "Luo ja tarkasta hyväksyttyjä sähköisiä allekirjoituksia.",
            assetName: "iphone-documents-fi.png"
        )
    ],
    "en-US": [
        SlideData(
            filename: "01-app-main.png",
            title: "Log in to web services with your identity card",
            subtitle: "You can also use your phone as a wireless card reader.",
            assetName: "iphone-main-en.png"
        ),
        SlideData(
            filename: "02-documents.png",
            title: "Sign documents",
            subtitle: "Create and verify qualified electronic signatures.",
            assetName: "iphone-documents-en.png"
        )
    ],
    "sv": [
        SlideData(
            filename: "01-app-main.png",
            title: "Identifiera dig till e-tjänster med identitetskort",
            subtitle: "Du kan även använda telefonen som trådlös kortläsare.",
            assetName: "iphone-main-sv.png"
        ),
        SlideData(
            filename: "02-documents.png",
            title: "Underteckna dokument",
            subtitle: "Skapa och granska kvalificerade elektroniska underskrifter.",
            assetName: "iphone-documents-sv.png"
        )
    ]
]

let ipadCatalog: [String: [SlideData]] = [
    "fi": [
        SlideData(
            filename: "01-main.png",
            title: "Tunnistaudu henkilökortilla verkkopalveluihin",
            subtitle: "Voit käyttää myös puhelinta langattomana kortinlukijana.",
            assetName: "ipad-main-fi.png"
        ),
        SlideData(
            filename: "02-documents.png",
            title: "Allekirjoita asiakirjoja",
            subtitle: "Luo ja tarkasta hyväksyttyjä sähköisiä allekirjoituksia.",
            assetName: "ipad-documents-fi.png"
        )
    ],
    "en-US": [
        SlideData(
            filename: "01-main.png",
            title: "Log in to web services with your identity card",
            subtitle: "You can also use your phone as a wireless card reader.",
            assetName: "ipad-main-en.png"
        ),
        SlideData(
            filename: "02-documents.png",
            title: "Sign documents",
            subtitle: "Create and verify qualified electronic signatures.",
            assetName: "ipad-documents-en.png"
        )
    ],
    "sv": [
        SlideData(
            filename: "01-main.png",
            title: "Identifiera dig till e-tjänster med identitetskort",
            subtitle: "Du kan även använda telefonen som trådlös kortläsare.",
            assetName: "ipad-main-sv.png"
        ),
        SlideData(
            filename: "02-documents.png",
            title: "Underteckna dokument",
            subtitle: "Skapa och granska kvalificerade elektroniska underskrifter.",
            assetName: "ipad-documents-sv.png"
        )
    ]
]

func parseArgs() -> (locales: [String], platforms: [String]) {
    var locales = ["fi"]
    var platforms = ["macos", "ios", "ipad"]
    var explicitPlatform = false

    let args = CommandLine.arguments
    var i = 1
    while i < args.count {
        if args[i] == "--locale" && i + 1 < args.count {
            let loc = args[i + 1]
            locales = (loc == "all") ? ["fi", "en-US", "sv"] : [loc]
            i += 2
        } else if args[i] == "--platform" && i + 1 < args.count {
            let plat = args[i + 1]
            platforms = (plat == "all") ? ["macos", "ios", "ipad"] : [plat]
            explicitPlatform = true
            i += 2
        } else {
            i += 1
        }
    }

    if !explicitPlatform && CommandLine.arguments.contains("--locale") {
        // If only --locale is passed, default to all platforms
        platforms = ["macos", "ios", "ipad"]
    }

    return (locales, platforms)
}

let (locales, platforms) = parseArgs()
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let assetsDir = repoRoot.appendingPathComponent("Metadata/screenshots/assets")
let goldenGatePNGURL = assetsDir.appendingPathComponent("golden-gate-dark.png")

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
    FileHandle.standardError.write(Data("Error: Failed to obtain sRGB color space.\n".utf8))
    exit(1)
}

let wallpaperImage = FileManager.default.fileExists(atPath: goldenGatePNGURL.path)
    ? NSImage(contentsOf: goldenGatePNGURL)
    : nil

func renderMacOS(locale: String, slide: SlideData) {
    let width = 2880
    let height = 1800
    let targetDir = repoRoot.appendingPathComponent("Metadata/screenshots/\(locale)/APP_DESKTOP")
    try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fatalError("Failed to allocate CGContext") }

    let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.current = nsContext

    // 1. Wallpaper
    if let bg = wallpaperImage {
        let imgW = bg.size.width
        let imgH = bg.size.height
        let scale = max(CGFloat(width) / imgW, CGFloat(height) / imgH)
        let drawW = imgW * scale
        let drawH = imgH * scale
        let drawX = (CGFloat(width) - drawW) / 2
        let drawY = (CGFloat(height) - drawH) / 2
        bg.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))

        // Dark top veil
        context.saveGState()
        let veilColors = [
            NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.10, alpha: 0.82).cgColor,
            NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.10, alpha: 0.35).cgColor,
            NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.10, alpha: 0.0).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: veilColors, locations: [0.0, 0.45, 1.0]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: width / 2, y: height), end: CGPoint(x: width / 2, y: 0), options: [])
        }
        context.restoreGState()
    } else {
        NSColor(calibratedRed: 0x1C/255.0, green: 0x1C/255.0, blue: 0x1E/255.0, alpha: 1.0).setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    var currentTopY = CGFloat(height) - 150

    // 2. Title
    let titleFontSize: CGFloat = slide.title.count > 45 ? 68 : 76
    let titleFont = NSFont.systemFont(ofSize: titleFontSize, weight: .bold)
    let titleStyle = NSMutableParagraphStyle()
    titleStyle.alignment = .center
    titleStyle.lineBreakMode = .byWordWrapping
    let titleAttr: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: NSColor.white,
        .paragraphStyle: titleStyle
    ]
    let titleRect = CGRect(x: 120, y: currentTopY - 110, width: CGFloat(width - 240), height: 110)
    (slide.title as NSString).draw(in: titleRect, withAttributes: titleAttr)
    currentTopY -= 130

    // 3. Subtitle
    let subFontSize: CGFloat = slide.subtitle.count > 80 ? 36 : 40
    let subFont = NSFont.systemFont(ofSize: subFontSize, weight: .medium)
    let subStyle = NSMutableParagraphStyle()
    subStyle.alignment = .center
    subStyle.lineBreakMode = .byWordWrapping
    let subAttr: [NSAttributedString.Key: Any] = [
        .font: subFont,
        .foregroundColor: NSColor(calibratedWhite: 0.84, alpha: 1.0),
        .paragraphStyle: subStyle
    ]
    let subRect = CGRect(x: 180, y: currentTopY - 100, width: CGFloat(width - 360), height: 100)
    (slide.subtitle as NSString).draw(in: subRect, withAttributes: subAttr)
    currentTopY -= 110

    // 4. Window Asset
    let windowURL = assetsDir.appendingPathComponent(slide.assetName)
    if let winImg = NSImage(contentsOf: windowURL) {
        let maxAvailableWidth = CGFloat(width) - 300
        let maxAvailableHeight = currentTopY - 60
        let imgW = winImg.size.width
        let imgH = winImg.size.height
        var scale = min(maxAvailableWidth / imgW, maxAvailableHeight / imgH)
        if scale > 2.05 { scale = 2.05 }
        let drawW = imgW * scale
        let drawH = imgH * scale
        let drawX = (CGFloat(width) - drawW) / 2
        let drawY = max(50, (currentTopY - drawH) / 2 + 25)
        winImg.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
    }

    // 5. Output
    guard let cgImage = context.makeImage() else { fatalError("Failed to render CGImage") }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = rep.representation(using: .png, properties: [:]) else { fatalError("Failed to encode PNG") }
    let destination = targetDir.appendingPathComponent(slide.filename)
    try? pngData.write(to: destination)
    print("Wrote \(destination.path) [\(width)x\(height), 0% alpha]")
}

func renderIOS(locale: String, slide: SlideData) {
    let width = 1290
    let height = 2796
    let targetDir = repoRoot.appendingPathComponent("Metadata/screenshots/\(locale)/APP_IPHONE_67")
    try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fatalError("Failed to allocate CGContext") }

    let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.current = nsContext

    // 1. Wallpaper
    if let bg = wallpaperImage {
        let imgW = bg.size.width
        let imgH = bg.size.height
        let scale = max(CGFloat(width) / imgW, CGFloat(height) / imgH)
        let drawW = imgW * scale
        let drawH = imgH * scale
        let drawX = (CGFloat(width) - drawW) / 2
        let drawY = (CGFloat(height) - drawH) / 2
        bg.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))

        // Dark top veil
        context.saveGState()
        let veilColors = [
            NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.10, alpha: 0.90).cgColor,
            NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.10, alpha: 0.50).cgColor,
            NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.10, alpha: 0.0).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: veilColors, locations: [0.0, 0.45, 1.0]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: width / 2, y: height), end: CGPoint(x: width / 2, y: height - 1150), options: [])
        }
        context.restoreGState()
    } else {
        NSColor(calibratedRed: 0x1C/255.0, green: 0x1C/255.0, blue: 0x1E/255.0, alpha: 1.0).setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    // 2. Title metrics
    let titleLength = slide.title.count
    let titleFontSize: CGFloat = titleLength > 36 ? 94 : (titleLength > 25 ? 100 : 108)
    let titleFont = NSFont.systemFont(ofSize: titleFontSize, weight: .bold)
    let titleStyle = NSMutableParagraphStyle()
    titleStyle.alignment = .center
    titleStyle.lineBreakMode = .byWordWrapping
    let titleAttr: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: NSColor.white,
        .paragraphStyle: titleStyle
    ]
    let titleBounding = (slide.title as NSString).boundingRect(
        with: CGSize(width: CGFloat(width - 100), height: 500),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: titleAttr
    )
    let titleHeight = ceil(titleBounding.height)

    // 3. Subtitle metrics
    let subLength = slide.subtitle.count
    let subFontSize: CGFloat = subLength > 50 ? 58 : 64
    let subFont = NSFont.systemFont(ofSize: subFontSize, weight: .medium)
    let subStyle = NSMutableParagraphStyle()
    subStyle.alignment = .center
    subStyle.lineBreakMode = .byWordWrapping
    let subAttr: [NSAttributedString.Key: Any] = [
        .font: subFont,
        .foregroundColor: NSColor(calibratedWhite: 0.88, alpha: 1.0),
        .paragraphStyle: subStyle
    ]
    let subBounding = (slide.subtitle as NSString).boundingRect(
        with: CGSize(width: CGFloat(width - 120), height: 400),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: subAttr
    )
    let subHeight = ceil(subBounding.height)

    // 4. Spatial Geometry & Hierarchy
    // Harmonized top-anchored alignment: Title starts at the exact same level across all slides (titleTopMargin = 236)
    let titleTopMargin: CGFloat = 236
    let titleToSubGap: CGFloat = titleHeight > 150 ? 56 : 64
    let phoneY: CGFloat = titleHeight > 150 ? 250 : 330

    let rawCropHeight: CGFloat = 1920
    let targetWidth: CGFloat = 1160
    let targetHeight = targetWidth * (rawCropHeight / 1290.0) // ~1726.5 px
    let phoneX = (CGFloat(width) - targetWidth) / 2
    let cornerRadius: CGFloat = 56.0

    let titleTopY = CGFloat(height) - titleTopMargin
    let titleBottomY = titleTopY - titleHeight
    let subTopY = titleBottomY - titleToSubGap
    let subBottomY = subTopY - subHeight

    let subRect = CGRect(x: 60, y: subBottomY, width: CGFloat(width - 120), height: subHeight)
    let titleRect = CGRect(x: 50, y: titleBottomY, width: CGFloat(width - 100), height: titleHeight)

    (slide.title as NSString).draw(in: titleRect, withAttributes: titleAttr)
    (slide.subtitle as NSString).draw(in: subRect, withAttributes: subAttr)

    // 5. Phone Screen presentation
    let phoneURL = assetsDir.appendingPathComponent(slide.assetName)
    if let phoneImg = NSImage(contentsOf: phoneURL) {

        // Bezel & Ambient Shadow
        context.saveGState()
        let bezelRect = CGRect(x: phoneX - 8, y: phoneY - 8, width: targetWidth + 16, height: targetHeight + 16)
        let bezelRadius = cornerRadius + 6.0
        let bezelPath = NSBezierPath(roundedRect: bezelRect, xRadius: bezelRadius, yRadius: bezelRadius)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.65)
        shadow.shadowBlurRadius = 50.0
        shadow.shadowOffset = NSSize(width: 0, height: -22)
        shadow.set()

        NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1.0).setFill()
        bezelPath.fill()
        context.restoreGState()

        // Bezel Highlight Stroke
        context.saveGState()
        let highlightPath = NSBezierPath(roundedRect: bezelRect, xRadius: bezelRadius, yRadius: bezelRadius)
        highlightPath.lineWidth = 1.5
        NSColor(calibratedRed: 0.32, green: 0.33, blue: 0.36, alpha: 0.85).setStroke()
        highlightPath.stroke()
        context.restoreGState()

        // Clipped Screen
        context.saveGState()
        let screenRect = CGRect(x: phoneX, y: phoneY, width: targetWidth, height: targetHeight)
        let screenPath = NSBezierPath(roundedRect: screenRect, xRadius: cornerRadius, yRadius: cornerRadius)
        screenPath.addClip()

        let imgW = phoneImg.size.width
        let imgH = phoneImg.size.height
        let sourceCropH = imgH * (rawCropHeight / 2796.0)
        let fromRect = CGRect(x: 0, y: imgH - sourceCropH, width: imgW, height: sourceCropH)
        phoneImg.draw(in: screenRect, from: fromRect, operation: .copy, fraction: 1.0)

        NSColor(calibratedWhite: 0.0, alpha: 0.25).setStroke()
        screenPath.lineWidth = 1.0
        screenPath.stroke()
        context.restoreGState()
    }

    // 5. Output
    guard let cgImage = context.makeImage() else { fatalError("Failed to render CGImage") }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = rep.representation(using: .png, properties: [:]) else { fatalError("Failed to encode PNG") }
    let destination = targetDir.appendingPathComponent(slide.filename)
    try? pngData.write(to: destination)
    print("Wrote \(destination.path) [\(width)x\(height), 0% alpha]")
}

func renderIPad(locale: String, slide: SlideData) {
    let width = 2048
    let height = 2732
    let targetDir = repoRoot.appendingPathComponent("Metadata/screenshots/\(locale)/APP_IPAD_PRO_3GEN_129")
    try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fatalError("Failed to allocate CGContext") }

    let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.current = nsContext

    // 1. Wallpaper
    if let bg = wallpaperImage {
        let imgW = bg.size.width
        let imgH = bg.size.height
        let scale = max(CGFloat(width) / imgW, CGFloat(height) / imgH)
        let drawW = imgW * scale
        let drawH = imgH * scale
        let drawX = (CGFloat(width) - drawW) / 2
        let drawY = (CGFloat(height) - drawH) / 2
        bg.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))

        // Dark top veil
        context.saveGState()
        let veilColors = [
            NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.10, alpha: 0.90).cgColor,
            NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.10, alpha: 0.50).cgColor,
            NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.10, alpha: 0.0).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: veilColors, locations: [0.0, 0.45, 1.0]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: width / 2, y: height), end: CGPoint(x: width / 2, y: height - 1300), options: [])
        }
        context.restoreGState()
    } else {
        NSColor(calibratedRed: 0x1C/255.0, green: 0x1C/255.0, blue: 0x1E/255.0, alpha: 1.0).setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    // 2. Title metrics
    let titleLength = slide.title.count
    let titleFontSize: CGFloat = titleLength > 45 ? 116 : (titleLength > 30 ? 126 : 136)
    let titleFont = NSFont.systemFont(ofSize: titleFontSize, weight: .bold)
    let titleStyle = NSMutableParagraphStyle()
    titleStyle.alignment = .center
    titleStyle.lineBreakMode = .byWordWrapping
    let titleAttr: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: NSColor.white,
        .paragraphStyle: titleStyle
    ]
    let titleBounding = (slide.title as NSString).boundingRect(
        with: CGSize(width: CGFloat(width - 160), height: 550),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: titleAttr
    )
    let titleHeight = ceil(titleBounding.height)

    // 3. Subtitle metrics
    let subLength = slide.subtitle.count
    let subFontSize: CGFloat = subLength > 55 ? 68 : 74
    let subFont = NSFont.systemFont(ofSize: subFontSize, weight: .medium)
    let subStyle = NSMutableParagraphStyle()
    subStyle.alignment = .center
    subStyle.lineBreakMode = .byWordWrapping
    let subAttr: [NSAttributedString.Key: Any] = [
        .font: subFont,
        .foregroundColor: NSColor(calibratedWhite: 0.88, alpha: 1.0),
        .paragraphStyle: subStyle
    ]
    let subBounding = (slide.subtitle as NSString).boundingRect(
        with: CGSize(width: CGFloat(width - 200), height: 400),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: subAttr
    )
    let subHeight = ceil(subBounding.height)

    // 4. Spatial Geometry & Hierarchy
    // Harmonized top-anchored alignment: Title starts at the exact same level across all slides (titleTopMargin = 280)
    let titleTopMargin: CGFloat = 280
    let titleToSubGap: CGFloat = titleHeight > 200 ? 64 : 72
    let ipadY: CGFloat = titleHeight > 200 ? 520 : 580

    let rawCropHeight: CGFloat = 1340
    let targetWidth: CGFloat = 1860
    let targetHeight = targetWidth * (rawCropHeight / 2048.0) // ~1217 px
    let ipadX = (CGFloat(width) - targetWidth) / 2
    let cornerRadius: CGFloat = 44.0

    let titleTopY = CGFloat(height) - titleTopMargin
    let titleBottomY = titleTopY - titleHeight
    let subTopY = titleBottomY - titleToSubGap
    let subBottomY = subTopY - subHeight

    let subRect = CGRect(x: 100, y: subBottomY, width: CGFloat(width - 200), height: subHeight)
    let titleRect = CGRect(x: 80, y: titleBottomY, width: CGFloat(width - 160), height: titleHeight)

    (slide.title as NSString).draw(in: titleRect, withAttributes: titleAttr)
    (slide.subtitle as NSString).draw(in: subRect, withAttributes: subAttr)

    // 5. iPad Screen presentation
    let ipadURL = assetsDir.appendingPathComponent(slide.assetName)
    if let ipadImg = NSImage(contentsOf: ipadURL) {

        // Bezel & Ambient Shadow
        context.saveGState()
        let bezelRect = CGRect(x: ipadX - 10, y: ipadY - 10, width: targetWidth + 20, height: targetHeight + 20)
        let bezelRadius = cornerRadius + 6.0
        let bezelPath = NSBezierPath(roundedRect: bezelRect, xRadius: bezelRadius, yRadius: bezelRadius)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.65)
        shadow.shadowBlurRadius = 55.0
        shadow.shadowOffset = NSSize(width: 0, height: -24)
        shadow.set()

        NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1.0).setFill()
        bezelPath.fill()
        context.restoreGState()

        // Bezel Highlight Stroke
        context.saveGState()
        let highlightPath = NSBezierPath(roundedRect: bezelRect, xRadius: bezelRadius, yRadius: bezelRadius)
        highlightPath.lineWidth = 1.5
        NSColor(calibratedRed: 0.32, green: 0.33, blue: 0.36, alpha: 0.85).setStroke()
        highlightPath.stroke()
        context.restoreGState()

        // Clipped Screen
        context.saveGState()
        let screenRect = CGRect(x: ipadX, y: ipadY, width: targetWidth, height: targetHeight)
        let screenPath = NSBezierPath(roundedRect: screenRect, xRadius: cornerRadius, yRadius: cornerRadius)
        screenPath.addClip()

        let imgW = ipadImg.size.width
        let imgH = ipadImg.size.height
        let sourceCropH = imgH * (rawCropHeight / 2732.0)
        let fromRect = CGRect(x: 0, y: imgH - sourceCropH, width: imgW, height: sourceCropH)
        ipadImg.draw(in: screenRect, from: fromRect, operation: .copy, fraction: 1.0)

        NSColor(calibratedWhite: 0.0, alpha: 0.25).setStroke()
        screenPath.lineWidth = 1.0
        screenPath.stroke()
        context.restoreGState()
    }

    // 5. Output
    guard let cgImage = context.makeImage() else { fatalError("Failed to render CGImage") }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = rep.representation(using: .png, properties: [:]) else { fatalError("Failed to encode PNG") }
    let destination = targetDir.appendingPathComponent(slide.filename)
    try? pngData.write(to: destination)
    print("Wrote \(destination.path) [\(width)x\(height), 0% alpha]")
}

for locale in locales {
    if platforms.contains("macos") {
        if let slides = macosCatalog[locale] {
            for slide in slides {
                renderMacOS(locale: locale, slide: slide)
            }
        }
    }

    if platforms.contains("ios") {
        if let slides = iosCatalog[locale] {
            for slide in slides {
                renderIOS(locale: locale, slide: slide)
            }
        }
    }

    if platforms.contains("ipad") {
        if let slides = ipadCatalog[locale] {
            for slide in slides {
                renderIPad(locale: locale, slide: slide)
            }
        }
    }
}
