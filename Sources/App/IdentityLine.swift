// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  /// The one line the identity row shows, chosen from the requester's facts.
  internal enum IdentityLine: Equatable, Sendable {
    /// The card has stayed present without an identity long enough to warn.
    case cardNotReady

    /// "Connect a card reader".
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

    /// A card in the reader is settling, or a read of the phone's card is
    /// in flight; the row shows nothing until the holder's name.
    case reading

    // MARK: Computed Properties

    /// Whether the row shows this line only once it has lasted.
    ///
    /// A phone connected before its card is read is on the way to the
    /// holder's name and not worth a flash; a connection that lasts is.
    internal var waitsBeforeShowing: Bool {
      switch self {
      case .phoneConnected:
        true

      case .cardNotReady, .connectReader, .empty, .holder, .insertCard, .phoneForgot, .reading:
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
        if facts.phonePresent, !facts.readInFlight, let phone = facts.pairedPhone {
          return .phoneConnected(phone)
        }
        return .reading

      case .noCard:
        if facts.readInFlight {
          return .reading
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
