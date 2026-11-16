// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The one line the identity row shows, chosen from the requester's facts.
///
/// A card in this computer's reader overrides the paired phone: while one is
/// there the line speaks of that card alone. Otherwise, where the remote card
/// is compiled in, a paired phone's line stands while the phone offers its
/// card; with no remote card, whether no phone is paired or the paired one
/// offers none, the line asks for a pairing code as if no phone were there,
/// and names neither the phone's state nor a reason (RAPP v26.11.8 §4.7). A
/// local-network denial stands in for the pairing code. With the remote card
/// compiled out the line speaks of this computer's reader alone.
public enum IdentityLine: Equatable, Sendable {
  /// The card in this computer's reader has stayed without an identity long
  /// enough to warn; the PIN codes stay one click away.
  case cardNotReady

  /// "Turn on remote use from the top right corner.": remote use is off and
  /// no reader is attached.
  case connectReader

  #if os(iOS)
    /// "Connecting to <phone>...": the phone its user has just paired, until
    /// its first card status or the redial window.
    case connectingToPairedPhone(String)
  #endif

  /// "Insert the card into the reader.": remote use is off and a reader is
  /// attached, empty.
  case insertCard

  #if os(iOS)
    /// Remote use on and the platform denies this app the local network,
    /// while no phone offers an identity: the error, with the settings one
    /// click away.
    case localNetworkDenied
  #endif

  /// The holder's name from the card in this computer's reader, beside the
  /// control that opens the PIN codes.
  case localHolder

  #if os(iOS)
    /// The paired phone's line.
    case paired(PairedLead)
  #endif

  #if os(iOS)
    /// Remote use on, no card here and no phone paired: the row asks for a
    /// phone's pairing code, an attached reader or not, so a document waiting
    /// to be signed can be signed on the phone once it is paired.
    case pairPhone
  #endif

  #if os(iOS)
    /// The phone, by name, announced it forgot this computer.
    case phoneForgot(String)
  #endif

  /// The card in this computer's reader is settling; it mints in well under a
  /// second, so the row shows nothing until the holder's name.
  case reading

  #if os(iOS)
    /// What the paired phone's line says.
    public enum PairedLead: Equatable, Sendable {
      /// The holder's name from the certificate the phone confirmed, then
      /// "(via phone)".
      case holder

      /// "Insert the card into the phone's card reader.": the phone reports
      /// no card in the card reader attached to it.
      case phoneReader
    }
  #endif

  // MARK: Static Functions

  /// The line for `facts`.
  public static func derive(_ facts: RequesterFacts) -> Self {
    if facts.cardPresent {
      switch facts.availability {
      case .ready:
        return .localHolder

      case .cardWithoutIdentity, .noCard:
        return facts.warnsUnavailableCard ? .cardNotReady : .reading
      }
    }
    #if os(iOS)
      guard facts.remoteUse else {
        return facts.readerConnected ? .insertCard : .connectReader
      }
      guard facts.phonePaired else {
        if let forgot = facts.phoneThatForgot {
          return .phoneForgot(forgot)
        }
        return facts.localNetworkDenied ? .localNetworkDenied : .pairPhone
      }
      guard let lead = pairedLead(facts) else {
        if facts.localNetworkDenied {
          return .localNetworkDenied
        }
        return facts.phoneJustPaired.map(Self.connectingToPairedPhone) ?? .pairPhone
      }
      return .paired(lead)
    #else
      return facts.readerConnected ? .insertCard : .connectReader
    #endif
  }

  #if os(iOS)
    /// What the paired phone's line says; the first rule that matches wins.
    ///
    /// The phone's word that its card reader is empty outranks an identity
    /// still offered in its grace (RAPP v26.11.8 §8.4 item 3). A phone
    /// without a card reader that reports no card leaves the identity it
    /// offers standing. Nil while the phone offers no card.
    private static func pairedLead(_ facts: RequesterFacts) -> PairedLead? {
      if PhoneCardRequest(facts.phoneCardStatus) == .insertIntoPhoneReader {
        return .phoneReader
      }
      return facts.availability == .ready ? .holder : nil
    }
  #endif
}
