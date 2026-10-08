// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Testing

  @testable import RefineID

  /// A connected reader disables the phone path: the prompt names the
  /// reader alone and asks for no pairing code.
  @MainActor
  @Suite
  internal struct RemotePairingPromptTests {
    @Test
    internal func readerConnectedShowsReaderOnly() {
      #expect(RemotePairingPromptView.content(readerConnected: true) == .readerOnly)
    }

    @Test
    internal func noReaderAsksForThePhoneCode() {
      #expect(RemotePairingPromptView.content(readerConnected: false) == .phoneCode)
    }
  }

#endif
