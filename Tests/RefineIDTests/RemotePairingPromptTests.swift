// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Testing

  @testable import RefineID

  /// A connected reader disables the phone path: the prompt names the
  /// reader alone and holds no pairing offer.
  @Suite
  internal struct RemotePairingPromptTests {
    @Test
    internal func readerConnectedShowsReaderOnly() {
      #expect(
        RemotePairingPromptView.content(phase: .offer("123456"), readerConnected: true)
          == .readerOnly
      )
    }

    @Test
    internal func noReaderShowsPhoneCode() {
      #expect(
        RemotePairingPromptView.content(phase: .offer("123456"), readerConnected: false)
          == .phoneCode(RappPairingCode.formatted("123456"))
      )
    }

    @Test
    internal func noReaderKeepsConnectingAndPreparing() {
      #expect(
        RemotePairingPromptView.content(phase: .connecting, readerConnected: false)
          == .connecting
      )
      #expect(
        RemotePairingPromptView.content(phase: .idle, readerConnected: false)
          == .preparing
      )
    }

    @Test
    internal func readerConnectedWantsNoOffer() {
      let phases: [RappPairingModel.Phase] = [
        .idle,
        .offer("123456"),
        .codeEntry,
        .connecting,
        .failed("Pairing could not be started"),
      ]
      for phase in phases {
        #expect(
          !RemotePairingPromptView.wantsOffer(phase: phase, readerConnected: true)
        )
      }
    }

    @Test
    internal func noReaderWantsOfferOnlyWhenNothingInFlight() {
      #expect(RemotePairingPromptView.wantsOffer(phase: .idle, readerConnected: false))
      #expect(
        RemotePairingPromptView.wantsOffer(
          phase: .failed("Pairing could not be started"),
          readerConnected: false
        )
      )
      #expect(
        !RemotePairingPromptView.wantsOffer(phase: .offer("123456"), readerConnected: false)
      )
      #expect(
        !RemotePairingPromptView.wantsOffer(phase: .connecting, readerConnected: false)
      )
    }
  }

#endif
