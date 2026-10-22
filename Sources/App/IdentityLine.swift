// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  /// The one line the identity row shows, chosen from the requester's facts.
  internal enum IdentityLine: Equatable, Sendable {
    /// The card has stayed present without an identity long enough to warn.
    case cardNotReady

    /// "Connecting…": the phone's card is on its way to the holder's name,
    /// read or about to be.
    case connecting

    /// Nothing worth a line: a paired phone that is not on the network
    /// leaves the row empty, and the pairing prompt below it stands.
    case empty

    /// The holder's name.
    case holder

    /// "Insert the card into the reader."
    case insertCard

    /// "Insert the card into the phone's card reader.": the paired phone
    /// says it holds no card.
    case insertCardInPhone

    /// Nothing here can sign, no reader card and no paired phone: the row
    /// asks for a phone's pairing code, so a document waiting to be signed
    /// can be signed on the phone once it is paired.
    case pairPhone

    /// The phone, by name, announced it forgot this computer.
    case phoneForgot(String)

    /// A card in the reader is settling; it mints in well under a second,
    /// so the row shows nothing until the holder's name.
    case reading

    // MARK: Static Functions

    /// The line for `facts`; the first rule that matches wins.
    ///
    /// The phone's word that it holds no card outranks an identity still
    /// offered in its grace (RAPP v26.10.22 §8.4 item 3): the row says what
    /// the holder can do now, while browsers keep the identity a little
    /// longer.
    internal static func derive(_ facts: RequesterFacts) -> Self {
      let phoneHoldsNoCard = facts.phoneReportsNoCard && !facts.cardPresent
      switch facts.availability {
      case .ready:
        return phoneHoldsNoCard ? .insertCardInPhone : .holder

      case .cardWithoutIdentity:
        if facts.cardPresent {
          return facts.warnsUnavailableCard ? .cardNotReady : .reading
        }
        return phoneHoldsNoCard ? .insertCardInPhone : .connecting

      case .noCard:
        if facts.readInFlight {
          return .connecting
        }
        if facts.readerConnected {
          return .insertCard
        }
        guard facts.pairedPhone != nil else {
          if let forgot = facts.phoneThatForgot {
            return .phoneForgot(forgot)
          }
          return .pairPhone
        }
        if phoneHoldsNoCard {
          return .insertCardInPhone
        }
        return facts.phonePresent ? .connecting : .empty
      }
    }
  }

#endif
