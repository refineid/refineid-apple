// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CoreGraphics
  import Foundation
  import Testing
  import Vision

  @testable import RefineID

  /// The portrait treatment may spend data correction, never structure.
  @Suite
  internal struct QrPortraitTests {
    /// A high-resolution square rendering with the required quiet zone.
    private static func image(of artwork: QrPortrait.Artwork) throws -> CGImage {
      let quietZone = 4
      let modulePixels = 8
      let imageSide = (artwork.side + quietZone * 2) * modulePixels
      var pixels = [UInt8](repeating: UInt8.max, count: imageSide * imageSide)
      for row in 0..<artwork.side {
        for column in 0..<artwork.side
        where artwork.treated[row * artwork.side + column] {
          let top = (row + quietZone) * modulePixels
          let left = (column + quietZone) * modulePixels
          for pixelRow in top..<(top + modulePixels) {
            for pixelColumn in left..<(left + modulePixels) {
              pixels[pixelRow * imageSide + pixelColumn] = 0
            }
          }
        }
      }
      let context = try #require(
        CGContext(
          data: &pixels,
          width: imageSide,
          height: imageSide,
          bitsPerComponent: UInt8.bitWidth,
          bytesPerRow: imageSide,
          space: CGColorSpaceCreateDeviceGray(),
          bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
      )
      return try #require(context.makeImage())
    }

    @Test
    internal func productionTreatmentPreservesEveryFunctionModule() throws {
      let qrCode = try #require(
        QrCode.modules(of: Data(String(repeating: "A", count: 244).utf8))
      )
      let portrait = try #require(
        PortraitHalftone.Map(
          side: qrCode.side,
          darkness: (0..<(qrCode.side * qrCode.side)).map { index in
            index.isMultiple(of: 2) ? 0.0 : 1.0
          }
        )
      )
      let artwork = try #require(
        QrPortrait.artwork(qr: qrCode, portrait: portrait)
      )

      for index in artwork.original.indices
      where artwork.functionModules[index] {
        #expect(artwork.original[index] == artwork.treated[index])
      }
      #expect(artwork.flippedCount == 0)
      #expect(artwork.side == 69)
    }

    @Test
    internal func noDamageLeavesTheMatrixUntouched() throws {
      let qrCode = try #require(QrCode.modules(of: Data("RID1/TEST".utf8)))
      let portrait = try #require(
        PortraitHalftone.Map(
          side: qrCode.side,
          darkness: [Double](
            repeating: 1,
            count: qrCode.side * qrCode.side
          )
        )
      )
      let artwork = try #require(
        QrPortrait.artwork(qr: qrCode, portrait: portrait, flipShare: 0)
      )

      #expect(artwork.original == artwork.treated)
      #expect(artwork.flippedCount == 0)
    }

    @Test
    internal func largerPortraitFieldReachesTheRendererUnchanged() throws {
      let qrCode = try #require(QrCode.modules(of: Data("RID1/TEST".utf8)))
      let fieldSide = qrCode.side + 2
      let fieldDarkness = [Double](
        repeating: 0.25,
        count: fieldSide * fieldSide
      )
      let portrait = try #require(
        PortraitHalftone.Map(
          side: qrCode.side,
          darkness: [Double](
            repeating: 0.75,
            count: qrCode.side * qrCode.side
          ),
          fieldSide: fieldSide,
          fieldDarkness: fieldDarkness
        )
      )
      let artwork = try #require(
        QrPortrait.artwork(qr: qrCode, portrait: portrait)
      )

      #expect(artwork.fieldSide == fieldSide)
      #expect(artwork.fieldDarkness == fieldDarkness)
    }

    @Test
    internal func mismatchedPortraitIsRefused() throws {
      let qrCode = try #require(QrCode.modules(of: Data("RID1/TEST".utf8)))
      let portrait = try #require(
        PortraitHalftone.Map(side: 1, darkness: [0])
      )

      #expect(QrPortrait.artwork(qr: qrCode, portrait: portrait) == nil)
    }

    @Test
    internal func productionTreatmentRemainsMachineReadable() throws {
      let payload = String(repeating: "A", count: 244)
      let qrCode = try #require(QrCode.modules(of: Data(payload.utf8)))
      let portrait = try #require(
        PortraitHalftone.Map(
          side: qrCode.side,
          darkness: (0..<(qrCode.side * qrCode.side)).map { index in
            index.isMultiple(of: 3) ? 0 : 1
          }
        )
      )
      let artwork = try #require(
        QrPortrait.artwork(qr: qrCode, portrait: portrait)
      )
      let request = VNDetectBarcodesRequest()
      request.symbologies = [.qr]

      try VNImageRequestHandler(cgImage: Self.image(of: artwork)).perform(
        [request]
      )

      #expect(request.results?.contains { $0.payloadStringValue == payload } == true)
    }
  }

#endif
