// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  /// The one line the identity row shows, chosen from the requester's facts.
  ///
  /// A card in this Mac's reader overrides the paired phone: while one is
  /// there the line speaks of that card alone. With remote use off the line
  /// speaks of this Mac's reader alone. Otherwise a paired phone's line
  /// stands, and with no phone paired the line asks for a pairing code;
  /// a local-network denial stands in for the pairing code and for a
  /// phone still connecting.
  internal enum IdentityLine: Equatable, Sendable {
    /// The card in this Mac's reader has stayed without an identity long
    /// enough to warn; the PIN codes stay one click away.
    case cardNotReady

    /// "Connect a card reader.": remote use is off and no reader is
    /// attached.
    case connectReader

    /// "Insert the card into the reader.": remote use is off and a reader
    /// is attached, empty.
    case insertCard

    /// The holder's name from the card in this Mac's reader, beside the
    /// control that opens the PIN codes.
    case localHolder

    /// Remote use on and macOS denies this app the local network, while
    /// no phone offers an identity: the error, with the settings one
    /// click away.
    case localNetworkDenied

    /// The paired phone's line.
    case paired(PairedLead)

    /// Remote use on, no card here and no phone paired: the row asks for a
    /// phone's pairing code, an attached reader or not, so a document
    /// waiting to be signed can be signed on the phone once it is paired.
    case pairPhone

    /// The phone, by name, announced it forgot this computer.
    case phoneForgot(String)

    /// The card in this Mac's reader is settling; it mints in well under a
    /// second, so the row shows nothing until the holder's name.
    case reading

    /// What the paired phone's line says.
    internal enum PairedLead: Equatable, Sendable {
      /// "Connecting to the phone…": the phone offers no identity yet.
      case connecting

      /// The holder's name from the certificate the phone confirmed, then
      /// "(via phone)".
      case holder

      /// "Insert the card into the phone's card reader.": the phone
      /// reports no card in the card reader attached to it.
      case phoneReader
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
      guard facts.remoteUse else {
        return facts.readerConnected ? .insertCard : .connectReader
      }
      guard facts.phonePaired else {
        if let forgot = facts.phoneThatForgot {
          return .phoneForgot(forgot)
        }
        return facts.localNetworkDenied ? .localNetworkDenied : .pairPhone
      }
      let lead = pairedLead(facts)
      if lead == .connecting, facts.localNetworkDenied {
        return .localNetworkDenied
      }
      return .paired(lead)
    }

    /// What the paired phone's line says; the first rule that matches
    /// wins.
    ///
    /// The phone's word that its card reader is empty outranks an identity
    /// still offered in its grace (RAPP v26.10.29 §8.4 item 3). A phone
    /// without a card reader that reports no card leaves the identity it
    /// offers standing.
    private static func pairedLead(_ facts: RequesterFacts) -> PairedLead {
      if PhoneCardRequest(facts.phoneCardStatus) == .insertIntoPhoneReader {
        return .phoneReader
      }
      return facts.availability == .ready ? .holder : .connecting
    }
  }

#endif
