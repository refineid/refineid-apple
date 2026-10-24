// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Testing

  @testable import RefineIDTestHost

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
          signature: nil
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
          signature: artwork
        )
      )

      #expect(mark.operators.contains(Self.handwritingSentinel))
      #expect(mark.operators.contains("-45.0000 -6.0000 m"))
      #expect(mark.operators.contains("0.0000 -19.0000 cm"))
      #expect(mark.operators.contains("0.0000 -27.0000 cm"))
      #expect(!mark.operators.contains("0.0000 5.0000 cm"))
    }
  }

#endif
