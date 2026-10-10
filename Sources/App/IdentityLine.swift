// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  /// The one line the identity row shows, chosen from the requester's facts.
  internal enum IdentityLine: Equatable, Sendable {
    /// The card has stayed present without an identity long enough to warn.
    case cardNotReady

    /// "Connect a card reader".
    case connectReader

    /// The holder's name.
    case holder

    /// "Insert the card into the reader".
    case insertCard

    /// "Phone connected".
    case phoneConnected

    /// "Phone connected", with Retry: the phone is here, its card was not
    /// read, and no read is under way.
    case phoneConnectedRetry

    /// "Reading the card…": a card in the reader is settling, or a read of
    /// the phone's card is in flight.
    case reading

    // MARK: Static Functions

    /// The line for `facts`; the first rule that matches wins.
    internal static func derive(_ facts: RequesterFacts) -> Self {
      switch facts.availability {
      case .ready:
        return .holder

      case .cardWithoutIdentity:
        if !facts.cardPresent, facts.phoneWaitsForCard {
          return .phoneConnectedRetry
        }
        return facts.warnsUnavailableCard ? .cardNotReady : .reading

      case .noCard:
        if facts.readInFlight {
          return .reading
        }
        if facts.readerConnected {
          return .insertCard
        }
        return facts.phonePresent ? .phoneConnected : .connectReader
      }
    }
  }

#endif
