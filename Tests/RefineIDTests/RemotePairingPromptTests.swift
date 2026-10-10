// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Testing

  @testable import RefineID

  /// The phone code is always asked for, and keeps only what a code holds.
  ///
  /// A connected reader adds its instruction beside the field.
  @MainActor
  @Suite
  internal struct RemotePairingPromptTests {
    @Test
    internal func readerConnectedKeepsThePhoneCode() {
      #expect(RemotePairingPromptView.content(readerConnected: true) == .phoneCodeBesideReader)
    }

    @Test
    internal func noReaderAsksForThePhoneCode() {
      #expect(RemotePairingPromptView.content(readerConnected: false) == .phoneCode)
    }

    @Test
    internal func typedCodeIsCanonicalized() {
      #expect(RemotePairingPromptView.limitedCode("7kx4m9") == "7KX4M9")
      #expect(RemotePairingPromptView.limitedCode("7K X4-M9") == "7KX4M9")
      #expect(RemotePairingPromptView.limitedCode("ol") == "01")
    }

    @Test
    internal func strayCharactersAreDroppedAlone() {
      #expect(RemotePairingPromptView.limitedCode("7K!X4") == "7KX4")
      #expect(RemotePairingPromptView.limitedCode("7KUX4") == "7KX4")
    }

    @Test
    internal func typedCodeStopsAtItsLength() {
      #expect(RemotePairingPromptView.limitedCode("7KX4M9AB") == "7KX4M9")
    }
  }

#endif
