#!/usr/bin/env swift
// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// Generate App Store marketing screenshots for RefineID macOS.
//
// Composes 2880x1800 (16:10) marketing screenshots with zero alpha channel,
// matching Apple App Store Connect specifications and legal standards.
// Uses official Apple desktop wallpapers and native UI language captures for each locale.
//
// Slide 1: Tunnistautuminen ja puhelintuki (Virtuaalikortti etusivulla)
// Slide 2: Dokumenttien allekirjoitus ja tarkastus (Allekirjoitusnäyttö)
//
// Usage:
//   swift Scripts/generate-store-screenshots.swift [--locale <fi|en-US|sv|all>]

import Cocoa

struct SlideData {
    let filename: String
    let title: String
    let subtitle: String
    let windowAsset: String
}

let catalog: [String: [SlideData]] = [
    "fi": [
        SlideData(
            filename: "01-authentication.png",
            title: "Tunnistaudu henkilökortilla verkkopalveluihin",
            subtitle: "Voit käyttää myös puhelinta langattomana kortinlukijana.",
            windowAsset: "window-card-fi.png"
        ),
        SlideData(
            filename: "02-documents.png",
            title: "Allekirjoita asiakirjoja",
            subtitle: "Luo ja tarkasta hyväksyttyjä sähköisiä allekirjoituksia.",
            windowAsset: "window-documents-fi.png"
        )
    ],
    "en-US": [
        SlideData(
            filename: "01-authentication.png",
            title: "Log in to web services with your identity card",
            subtitle: "You can also use your phone as a wireless card reader.",
            windowAsset: "window-card-en.png"
        ),
        SlideData(
            filename: "02-documents.png",
            title: "Sign documents",
            subtitle: "Create and verify qualified electronic signatures.",
            windowAsset: "window-documents-en.png"
        )
    ],
    "sv": [
        SlideData(
            filename: "01-authentication.png",
            title: "Identifiera dig till e-tjänster med identitetskort",
            subtitle: "Du kan även använda telefonen som trådlös kortläsare.",
            windowAsset: "window-card-sv.png"
        ),
        SlideData(
            filename: "02-documents.png",
            title: "Underteckna dokument",
            subtitle: "Skapa och granska kvalificerade elektroniska underskrifter.",
            windowAsset: "window-documents-sv.png"
        )
    ]
]

func parseLocale() -> [String] {
    let args = CommandLine.arguments
    for i in 0..<args.count {
        if args[i] == "--locale" && i + 1 < args.count {
            let loc = args[i + 1]
            if loc == "all" { return ["fi", "en-US", "sv"] }
            return [loc]
        }
    }
    return ["fi"]
}

let locales = parseLocale()
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()

let width = 2880
let height = 1800

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
    FileHandle.standardError.write(Data("Error: Failed to obtain sRGB color space.\n".utf8))
    exit(1)
}

let assetsDir = repoRoot.appendingPathComponent("Metadata/screenshots/assets")
let goldenGatePNGURL = assetsDir.appendingPathComponent("golden-gate-dark.png")
let wallpaperImage = FileManager.default.fileExists(atPath: goldenGatePNGURL.path)
    ? NSImage(contentsOf: goldenGatePNGURL)
    : nil

for locale in locales {
    guard let slides = catalog[locale] else {
        FileHandle.standardError.write(Data("Unknown locale: \(locale)\n".utf8))
        continue
    }

    let targetDir = repoRoot.appendingPathComponent("Metadata/screenshots/\(locale)/APP_DESKTOP")
    try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

    for slide in slides {
        // Strict CGImageAlphaInfo.noneSkipLast eliminates any alpha channel for App Store Connect
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            fatalError("Failed to allocate CGContext")
        }

        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext

        // 1. Draw Apple Official Desktop Wallpaper (aspect-fill centered)
        if let bg = wallpaperImage {
            let imgW = bg.size.width
            let imgH = bg.size.height
            let scale = max(CGFloat(width) / imgW, CGFloat(height) / imgH)
            let drawW = imgW * scale
            let drawH = imgH * scale
            let drawX = (CGFloat(width) - drawW) / 2
            let drawY = (CGFloat(height) - drawH) / 2
            bg.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))

            // Soft dark top veil for text readability while preserving Apple wallpaper aesthetics
            context.saveGState()
            let veilColors = [
                NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.10, alpha: 0.82).cgColor,
                NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.10, alpha: 0.35).cgColor,
                NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.10, alpha: 0.0).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: veilColors, locations: [0.0, 0.45, 1.0]) {
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: width / 2, y: height),
                    end: CGPoint(x: width / 2, y: 0),
                    options: []
                )
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

        // 4. Load and Draw Window Asset (Native Locale)
        let windowURL = assetsDir.appendingPathComponent(slide.windowAsset)
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

        // 5. Write PNG with strict zero alpha
        guard let cgImage = context.makeImage() else {
            fatalError("Failed to render CGImage")
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            fatalError("Failed to encode PNG representation")
        }

        let destination = targetDir.appendingPathComponent(slide.filename)
        do {
            try pngData.write(to: destination)
            print("Wrote \(destination.path) [\(width)x\(height), 0% alpha]")
        } catch {
            FileHandle.standardError.write(Data("Error writing to \(destination.path): \(error)\n".utf8))
        }
    }
}
