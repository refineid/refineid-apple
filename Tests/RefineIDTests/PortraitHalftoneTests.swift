// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CoreGraphics
  import Foundation
  import ImageIO
  import Testing
  import UniformTypeIdentifiers

  @testable import RefineID

  /// The biometric image becomes only a bounded greyscale module grid.
  @Suite
  internal struct PortraitHalftoneTests {
    /// A tiny half-black, half-white PNG made without a personal fixture.
    private static func splitImage() throws -> Data {
      let side = 16
      var pixels = [UInt8](repeating: UInt8.max, count: side * side)
      for row in 0..<side {
        for column in 0..<(side / 2) {
          pixels[row * side + column] = 0
        }
      }
      let context = try #require(
        CGContext(
          data: &pixels,
          width: side,
          height: side,
          bitsPerComponent: UInt8.bitWidth,
          bytesPerRow: side,
          space: CGColorSpaceCreateDeviceGray(),
          bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
      )
      let image = try #require(context.makeImage())
      let data = NSMutableData()
      let destination = try #require(
        CGImageDestinationCreateWithData(
          data,
          UTType.png.identifier as CFString,
          1,
          nil
        )
      )
      CGImageDestinationAddImage(destination, image, nil)
      try #require(CGImageDestinationFinalize(destination))
      return data as Data
    }

    @Test
    internal func imageBecomesAContrastingSquareMap() throws {
      let map = try #require(
        PortraitHalftone.map(imageData: Self.splitImage(), side: 12)
      )

      #expect(map.side == 12)
      #expect(map.darkness.count == 144)
      #expect(map.darkness.allSatisfy { (0...1).contains($0) })
      #expect((map.darkness.max() ?? 0) - (map.darkness.min() ?? 0) > 0.5)
    }

    @Test
    internal func extendedFieldSuppliesTheQrToneMap() throws {
      let image = try Self.splitImage()
      let map = try #require(
        PortraitHalftone.map(
          imageData: image,
          side: 12,
          fieldSide: 16
        )
      )

      #expect(map.fieldSide == 16)
      #expect(map.fieldDarkness.count == 256)
      let inset = 2
      for index in map.darkness.indices {
        let row = index / map.side + inset
        let column = index % map.side + inset
        #expect(
          map.darkness[index]
            == map.fieldDarkness[row * map.fieldSide + column]
        )
      }
    }

    @Test
    internal func invalidImageOrSideIsRefused() {
      #expect(PortraitHalftone.map(imageData: Data(), side: 12) == nil)
      #expect(
        PortraitHalftone.map(
          imageData: Data("not an image".utf8), side: 0
        ) == nil
      )
      #expect(
        PortraitHalftone.map(
          imageData: Data("not an image".utf8),
          side: 12,
          fieldSide: 15
        ) == nil
      )
    }
  }

#endif
