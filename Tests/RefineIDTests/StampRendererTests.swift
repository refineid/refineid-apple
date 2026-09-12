// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Testing

  @testable import RefineID

  /// Direct geometry checks for handwritten and identity-only stamps.
  @Suite
  internal struct StampRendererTests {
    private static let handwritingSentinel = "0 0 m 1 1 l S\n"

    @Test
    internal func identityOnlyStampCentresNameAndIdentifier() {
      let mark = StampRenderer.mark(
        StampRenderer.Statement(
          name: "Example Person",
          identifier: "TEST-IDENTIFIER",
          signature: nil,
          givenName: "",
          surname: ""
        )
      )

      #expect(mark.radius == 64)
      #expect(mark.operators.contains("0.0000 5.0000 cm"))
      #expect(mark.operators.contains("0.0000 -10.0000 cm"))
      #expect(!mark.operators.contains(Self.handwritingSentinel))
      #expect(!mark.operators.contains("-45.0000 -6.0000 m"))
      #expect(!mark.operators.lowercased().contains("nan"))
      #expect(!mark.operators.lowercased().contains("inf"))
    }

    @Test
    internal func handwrittenStampKeepsItsExistingLowerIdentityLayout() {
      let artwork = SignatureArtwork.Artwork(
        operators: Self.handwritingSentinel,
        width: 2,
        height: 2,
        inkLeft: 0,
        inkRight: 2,
        inkBottom: 0,
        inkTop: 2
      )
      let mark = StampRenderer.mark(
        StampRenderer.Statement(
          name: "Example Person",
          identifier: "TEST-IDENTIFIER",
          signature: artwork,
          givenName: "",
          surname: ""
        )
      )

      #expect(mark.operators.contains(Self.handwritingSentinel))
      #expect(mark.operators.contains("-45.0000 -6.0000 m"))
      #expect(mark.operators.contains("0.0000 -19.0000 cm"))
      #expect(mark.operators.contains("0.0000 -27.0000 cm"))
      #expect(!mark.operators.contains("0.0000 5.0000 cm"))
    }

    @Test
    internal func portraitQrUsesTheLargeRingAndOnlyRedHandwriting() {
      let artwork = SignatureArtwork.Artwork(
        operators: Self.handwritingSentinel,
        width: 2,
        height: 2,
        inkLeft: 0,
        inkRight: 2,
        inkBottom: 0,
        inkTop: 2
      )
      let side = 21
      let count = side * side
      let qrArtwork = QrPortrait.Artwork(
        original: [Bool](repeating: true, count: count),
        treated: [Bool](repeating: true, count: count),
        functionModules: [Bool](repeating: true, count: count),
        darkness: [Double](repeating: 0.5, count: count),
        side: side,
        flippedCount: 0,
        fieldSide: side,
        fieldDarkness: [Double](repeating: 0.5, count: count)
      )

      let mark = StampRenderer.mark(
        StampRenderer.Statement(
          name: "MUST NOT APPEAR",
          identifier: "MUST-NOT-APPEAR",
          signature: artwork,
          qrPortrait: qrArtwork,
          givenName: "Example",
          surname: "Person"
        )
      )

      #expect(mark.radius == 72)
      #expect(mark.operators.contains(Self.handwritingSentinel))
      #expect(
        mark.operators.contains(
          "q 15.0000 0 0 15.0000 -15.0000 -15.0000 cm"
        )
      )
      #expect(mark.operators.contains("h W n"))
      #expect(mark.operators.contains("1 1 1 rg"))
      #expect(mark.operators.contains("0 0 0 rg"))
      #expect(mark.operators.components(separatedBy: " re f\n").count == 2)
      #expect(!mark.operators.contains("-45.0000 -6.0000 m"))
      #expect(!mark.operators.contains("0.0000 -19.0000 cm"))
    }

    @Test
    internal func portraitNamesAreCurvedVectorOutlines() {
      let operators = StampRenderer.portraitCurvedNames(
        givenName: "Given",
        surname: "Family"
      )

      #expect(operators.components(separatedBy: " cm\n").count == 12)
      #expect(operators.contains("\nf\n"))
      #expect(!operators.contains("GIVEN"))
      #expect(!operators.contains("FAMILY"))
      #expect(!operators.contains("Tj"))
      #expect(
        StampRenderer.portraitCurvedNames(givenName: "", surname: "").isEmpty
      )
    }

    @Test
    internal func portraitQrDoesNotRequireHandwriting() {
      let side = 21
      let count = side * side
      let qrArtwork = QrPortrait.Artwork(
        original: [Bool](repeating: true, count: count),
        treated: [Bool](repeating: true, count: count),
        functionModules: [Bool](repeating: true, count: count),
        darkness: [Double](repeating: 0.5, count: count),
        side: side,
        flippedCount: 0,
        fieldSide: side,
        fieldDarkness: [Double](repeating: 0.5, count: count)
      )
      let mark = StampRenderer.mark(
        StampRenderer.Statement(
          name: "Example Person",
          identifier: "TEST-IDENTIFIER",
          signature: nil,
          qrPortrait: qrArtwork,
          givenName: "Given",
          surname: "Family"
        )
      )

      #expect(mark.radius == 72)
      #expect(mark.operators.contains("h W n"))
      #expect(!mark.operators.contains(Self.handwritingSentinel))
      // Eleven outlined name glyphs plus the stamp's outer transform.
      #expect(mark.operators.components(separatedBy: " cm\n").count == 13)
    }

    @Test
    internal func portraitFieldReachesTheRingOnTheSameModuleGrid() {
      #expect(StampRenderer.portraitFieldSide(forQrSide: 65) == 91)
      #expect(StampRenderer.portraitFieldSide(forQrSide: 69) == 97)
      #expect(StampRenderer.portraitFieldSide(forQrSide: 0) == nil)
    }

    @Test
    internal func portraitFieldContinuesBothQrDotResolutions() {
      let choices = (0..<32).flatMap { row in
        (0..<32).map { column in
          StampRenderer.portraitExtensionUsesCentralDot(
            row: row,
            column: column
          )
        }
      }
      let centralCount = choices.count { $0 }

      #expect((320...500).contains(centralCount))
      #expect(Set(choices).count == 2)
    }

    @Test
    internal func whitePortraitPixelsAddNoInventedDots() {
      let signature = SignatureArtwork.Artwork(
        operators: Self.handwritingSentinel,
        width: 2,
        height: 2,
        inkLeft: 0,
        inkRight: 2,
        inkBottom: 0,
        inkTop: 2
      )
      let side = 21
      let fieldSide = 31
      let qrArtwork = QrPortrait.Artwork(
        original: [Bool](repeating: false, count: side * side),
        treated: [Bool](repeating: false, count: side * side),
        functionModules: [Bool](repeating: false, count: side * side),
        darkness: [Double](repeating: 0, count: side * side),
        side: side,
        flippedCount: 0,
        fieldSide: fieldSide,
        fieldDarkness: [Double](repeating: 0, count: fieldSide * fieldSide)
      )

      let mark = StampRenderer.mark(
        StampRenderer.Statement(
          name: "MUST NOT APPEAR",
          identifier: "MUST-NOT-APPEAR",
          signature: signature,
          qrPortrait: qrArtwork,
          givenName: "",
          surname: ""
        )
      )

      #expect(!mark.operators.contains("h f\n"))
    }
  }

#endif
