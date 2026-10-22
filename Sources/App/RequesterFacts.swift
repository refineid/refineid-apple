// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  import RappEngine

  /// What the requester knows when it picks the identity line.
  internal struct RequesterFacts: Equatable, Sendable {
    /// What the token and the card's presence say together.
    internal var availability: LoginIdentityModel.Availability

    /// A card has been present without an identity long enough to warn.
    internal var warnsUnavailableCard: Bool

    /// A read of the phone's certificate is in flight.
    internal var readInFlight: Bool

    /// A reader is attached.
    internal var readerConnected: Bool

    /// A card is in a reader attached to this computer.
    internal var cardPresent: Bool

    /// The paired phone is in sight, on the network or over Bluetooth.
    internal var phonePresent: Bool

    /// The paired phone, by the name it introduced itself with; nil while
    /// no usable pairing exists.
    internal var pairedPhone: String?

    /// The phone that announced it forgot this computer, by name.
    internal var phoneThatForgot: String?

    /// The phone's latest `card.status` on the open session; nil without a
    /// session or before its first report.
    internal var phoneCardStatus: RappCardStatus?
  }

#endif
