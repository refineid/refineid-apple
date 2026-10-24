// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import Foundation

  /// A demonstration's paired phone: the virtual card served by a phone
  /// over an open session, with remote use on.
  ///
  /// A virtual card sits in a virtual reader, and no phone pairs with a
  /// demonstration, so without this the paired phone's line could only be
  /// shown with a real phone. The line, the switch and the window around
  /// them are the ones a holder sees; only the facts are given.
  ///
  /// Development builds only. Release builds contain none of this type or
  /// its argument.
  @MainActor
  internal enum DemoPairedPhone {
    /// The launch argument that shows the paired phone.
    internal static let launchArgument = "--mock-remote-connected"

    /// Whether this run shows the paired phone.
    internal static var isShown: Bool {
      DemoMode.shared.isActive
        && ProcessInfo.processInfo.arguments.contains(Self.launchArgument)
    }

    /// The requester's facts with the virtual card in the paired phone.
    internal static func facts(
      availability: LoginIdentityModel.Availability
    ) -> RequesterFacts {
      RequesterFacts(
        availability: availability,
        warnsUnavailableCard: false,
        readerConnected: false,
        cardPresent: false,
        remoteUse: true,
        phonePaired: true,
        phoneThatForgot: nil,
        phoneCardStatus: nil
      )
    }
  }

#endif
