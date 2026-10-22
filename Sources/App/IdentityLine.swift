// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  /// The one line the identity row shows, chosen from the requester's facts.
  ///
  /// A card in this Mac's reader overrides the paired phone: while one is
  /// there the line speaks of that card alone. Otherwise a paired phone
  /// names itself after whatever the line says, beside the control that
  /// forgets it, and with no phone paired the line asks for a pairing code.
  internal enum IdentityLine: Equatable, Sendable {
    /// The card in this Mac's reader has stayed without an identity long
    /// enough to warn; the PIN codes stay one click away.
    case cardNotReady

    /// "Insert the card into the reader.": a reader is attached, empty, and
    /// no phone is paired.
    case insertCard

    /// The holder's name from the card in this Mac's reader, beside the
    /// control that opens the PIN codes.
    case localHolder

    /// The paired phone: what it says, then its name, beside the control
    /// that forgets the pairing.
    case paired(PairedLead, phone: String)

    /// No card here and no phone paired: the row asks for a phone's pairing
    /// code, so a document waiting to be signed can be signed on the phone
    /// once it is paired.
    case pairPhone

    /// The phone, by name, announced it forgot this computer.
    case phoneForgot(String)

    /// The card in this Mac's reader is settling; it mints in well under a
    /// second, so the row shows nothing until the holder's name.
    case reading

    /// What the line says before the paired phone's name.
    internal enum PairedLead: Equatable, Sendable {
      /// Nothing: the phone is not in sight, and its name stands alone.
      case away

      /// "Connecting...": the phone's card is on its way to the holder's
      /// name, read or about to be.
      case connecting

      /// The holder's name, from the certificate the phone confirmed.
      case holder

      /// "Insert the card into the reader.": this Mac's own reader is
      /// attached and empty, and the phone has no card on offer.
      case insertCard

      /// "Insert the card into the phone's card reader." or "Place the card
      /// on the phone.": the phone says it holds no card, and whether a
      /// reader is attached to it picks which (RAPP v26.10.22 §8.4 item 6).
      case phoneCard(PhoneCardRequest)
    }

    // MARK: Static Functions

    /// The line for `facts`.
    internal static func derive(_ facts: RequesterFacts) -> Self {
      if facts.cardPresent {
        switch facts.availability {
        case .ready:
          return .localHolder

        case .cardWithoutIdentity, .noCard:
          return facts.warnsUnavailableCard ? .cardNotReady : .reading
        }
      }
      guard let phone = facts.pairedPhone else {
        if facts.readerConnected {
          return .insertCard
        }
        if let forgot = facts.phoneThatForgot {
          return .phoneForgot(forgot)
        }
        return .pairPhone
      }
      return .paired(pairedLead(facts), phone: phone)
    }

    /// What the paired phone's line says first; the first rule that matches
    /// wins.
    ///
    /// The phone's word that it holds no card outranks an identity still
    /// offered in its grace (RAPP v26.10.22 §8.4 item 3): the row says what
    /// the holder can do now, while browsers keep the identity a little
    /// longer.
    private static func pairedLead(_ facts: RequesterFacts) -> PairedLead {
      let phoneRequest = PhoneCardRequest(facts.phoneCardStatus)
      switch facts.availability {
      case .ready:
        return phoneRequest.map(PairedLead.phoneCard) ?? .holder

      case .cardWithoutIdentity:
        return phoneRequest.map(PairedLead.phoneCard) ?? .connecting

      case .noCard:
        if facts.readInFlight {
          return .connecting
        }
        if facts.readerConnected {
          return .insertCard
        }
        if let phoneRequest {
          return .phoneCard(phoneRequest)
        }
        return facts.phonePresent ? .connecting : .away
      }
    }
  }

#endif
