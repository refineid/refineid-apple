// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

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

    /// The presence browser reports the paired phone.
    internal var phonePresent: Bool

    /// A phone is paired with this computer.
    internal var paired: Bool
  }

#endif
