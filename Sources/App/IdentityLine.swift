// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  /// The one line the identity row shows, chosen from the requester's facts.
  internal enum IdentityLine: Equatable, Sendable {
    /// The card has stayed present without an identity long enough to warn.
    case cardNotReady

    /// "Connecting…": the phone's card is on its way to the holder's name,
    /// read or about to be.
    case connecting

    /// "Connect a card reader."
    case connectReader

    /// Nothing worth a line: a paired phone that is not on the network
    /// leaves the row empty, and the pairing prompt below it stands.
    case empty

    /// The holder's name.
    case holder

    /// "Insert the card into the reader."
    case insertCard

    /// The paired phone, by name, is on the network.
    case phoneConnected(String)

    /// The phone, by name, announced it forgot this computer.
    case phoneForgot(String)

    /// A card in the reader is settling; it mints in well under a second,
    /// so the row shows nothing until the holder's name.
    case reading

    // MARK: Computed Properties

    /// Whether the row shows this line only once it has lasted.
    ///
    /// A phone connected before its card reports is on the way to the
    /// holder's name, and the row says it is connecting; a connection that
    /// lasts without a card is named.
    internal var waitsBeforeShowing: Bool {
      switch self {
      case .phoneConnected:
        true

      case .cardNotReady, .connectReader, .connecting, .empty, .holder, .insertCard, .phoneForgot,
        .reading:
        false
      }
    }

    // MARK: Static Functions

    /// The line for `facts`; the first rule that matches wins.
    internal static func derive(_ facts: RequesterFacts) -> Self {
      switch facts.availability {
      case .ready:
        return .holder

      case .cardWithoutIdentity:
        if facts.cardPresent {
          return facts.warnsUnavailableCard ? .cardNotReady : .reading
        }
        return .connecting

      case .noCard:
        if facts.readInFlight {
          return .connecting
        }
        if facts.readerConnected {
          return .insertCard
        }
        guard let phone = facts.pairedPhone else {
          if let forgot = facts.phoneThatForgot {
            return .phoneForgot(forgot)
          }
          return .connectReader
        }
        return facts.phonePresent ? .phoneConnected(phone) : .empty
      }
    }
  }

#endif
