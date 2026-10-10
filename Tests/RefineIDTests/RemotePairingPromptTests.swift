// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Testing

  @testable import RefineID

  /// The phone code is always asked for; a connected reader adds its
  /// instruction beside it.
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
  }

#endif
