// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// Opening the card for one operation: in the clear, or with PACE and the
/// card access number or the operation's PIN.
extension CardMaintenance {
  /// The credential an operation spends, offered to open an organization
  /// card on an antenna: such a card opens its PACE channel with PIN 1,
  /// PIN 2 or the PUK in place of a card access number (FINEID S1 v4.0,
  /// organizational cards, section 2.1; FINEID S4-2 v4.0 sections 4.2 and
  /// 6), and a completed PACE counts as that credential verified.
  internal enum ChannelPin: Sendable {
    case pin1(String)
    case pin2(String)
    case puk(String)
  }

  /// What opens a sealed card for one operation.
  ///
  /// A citizen card on an antenna opens with its card access number; an
  /// organization card there opens with the credential the operation
  /// spends, and `refused` answers the operation when the card refuses it.
  internal struct CardOpener<Answer>: Sendable {
    /// The card access number offered, or nil for the one in memory.
    internal let cardAccessNumber: String?

    /// The PIN the operation spends, offered to an organization card.
    internal let channelPin: ChannelPin?

    /// The operation's answer to a refused credential, given the plain
    /// operations the card's state can still be read over.
    internal let refused: (@Sendable (Outcome, CardOperations) -> Answer)?

    /// The card access number alone.
    internal static func cardAccessNumber(_ digits: String?) -> Self {
      Self(cardAccessNumber: digits, channelPin: nil, refused: nil)
    }

    /// The card access number, and `pin` for an organization card.
    internal static func pin(
      _ pin: ChannelPin,
      cardAccessNumber digits: String?,
      refused: @escaping @Sendable (Outcome, CardOperations) -> Answer
    ) -> Self {
      Self(cardAccessNumber: digits, channelPin: pin, refused: refused)
    }
  }

  /// An entry its credential's type does not accept; nothing was sent.
  private struct ChannelEntryRefused: Error {}

  /// What opening the card for an operation came to.
  internal enum Opening {
    /// The card answers through these operations.
    case opened(CardOperations)

    /// The card refused the offered credential, at the floor or at the
    /// handshake; the plain operations still reach the card.
    case refused(Outcome, CardOperations)

    /// No channel could be opened.
    case unavailable
  }

  /// What `work` answers on an opened card, what `refused` answers for a
  /// refused PIN, and nothing when no channel opened.
  internal static func answer<Answer>(
    _ opening: Opening,
    refused: ((Outcome, CardOperations) -> Answer)?,
    _ work: (CardOperations) -> Answer?
  ) -> Answer? {
    switch opening {
    case .opened(let operations):
      work(operations)

    case .refused(let outcome, let plain):
      refused?(outcome, plain)

    case .unavailable:
      nil
    }
  }

  /// Opens the card for one operation: in the clear, with PACE and the
  /// card access number, or with PACE and the operation's PIN.
  ///
  /// The card's own answer decides. A citizen card on an antenna refuses
  /// the application with `6982` until PACE with its card access number.
  /// An organization card on an antenna answers `6985` until PACE with a
  /// PIN, to the select or to the reads after it, so when the operation
  /// spends a PIN a select that succeeds is followed by one read to tell;
  /// without a PIN offered, such a card stays closed, since no card
  /// access number opens it.
  internal static func openedOperations<Answer>(
    over channel: any CardChannel,
    opener: CardOpener<Answer>
  ) -> Opening {
    let cardAccessNumber = opener.cardAccessNumber
    let channelPin = opener.channelPin
    let operations = CardOperations(channel: channel)
    do {
      try operations.selectFineidApplication()
      // The card's answer tells, not its answer to reset: the phone's own
      // antenna reports an organization card's answer without the prefix
      // a reader synthesizes for a contactless card (observed on
      // hardware). A card in the clear answers the read; one that waits
      // for PACE with a PIN answers 6985.
      guard let channelPin else {
        return .opened(operations)
      }
      do {
        _ = try operations.readChipSerial()
        return .opened(operations)
      } catch  where CardOperationError.refusesBeforePace(error) {
        return pinOpenedOperations(over: channel, pin: channelPin)
      } catch {
        return .unavailable
      }
    } catch  where CardOperationError.refusesBeforePace(error) {
      guard let channelPin else { return .unavailable }
      return pinOpenedOperations(over: channel, pin: channelPin)
    } catch {
      return canOpenedOperations(over: channel, cardAccessNumber: cardAccessNumber)
    }
  }

  /// The card access number a citizen card on an antenna is opened with.
  ///
  /// The one the operation offers; else the first of the numbers the
  /// token driver tries, the app's own and the per-card library the
  /// driver fills as cards open (``CardCredentialStore/cardAccessNumberCandidates()``),
  /// so the window opens a card with the number its login used; else the
  /// one a prime holds. A card answers with no identifier before PACE, so
  /// the first is tried, and a refusal forgets them all.
  internal static func offeredAccessNumber(_ digits: String?) -> CardCanOffer.Candidate? {
    if let digits, let number = CardAccessNumber(digits: digits) {
      return CardCanOffer.Candidate(digits: digits, number: number)
    }
    if let first = CardCredentialStore.cardAccessNumberCandidates().first {
      return first
    }
    guard
      let primed = PrimeStore.storedIdentities().first?.can,
      let number = CardAccessNumber(digits: primed)
    else {
      return nil
    }
    return CardCanOffer.Candidate(digits: primed, number: number)
  }

  /// PACE with the card access number ``offeredAccessNumber(_:)`` names.
  private static func canOpenedOperations(
    over channel: any CardChannel,
    cardAccessNumber: String?
  ) -> Opening {
    guard let offered = offeredAccessNumber(cardAccessNumber) else { return .unavailable }
    let keys: PaceSessionKeys
    do {
      keys = try PaceEstablishment(channel: channel)
        .establish(with: PacePassword(cardAccessNumber: offered.number)).keys
    } catch PaceEstablishment.Failure.authenticationTokenMismatch {
      CardCredentialStore.forgetEveryCardAccessNumber()
      return .unavailable
    } catch PaceEstablishment.Failure.cardRejected(.authenticationFailed) {
      CardCredentialStore.forgetEveryCardAccessNumber()
      return .unavailable
    } catch {
      return .unavailable
    }
    let secure = SecureMessagingChannel(wrapping: channel, sessionKeys: keys)
    let secureOperations = CardOperations(channel: secure)
    guard (try? secureOperations.selectFineidApplication()) != nil else {
      return .unavailable
    }
    return .opened(secureOperations)
  }

  /// PACE with the operation's credential, the retry floor applied to the
  /// state MSE:Set AT reports before any try is spent.
  private static func pinOpenedOperations(
    over channel: any CardChannel,
    pin: ChannelPin
  ) -> Opening {
    let plain = CardOperations(channel: channel)
    let role: CredentialRole
    let established: PaceEstablishment.Established
    do {
      (role, established) = try establishedChannel(over: channel, pin: pin)
    } catch {
      return .refused(paceRefusal(error), plain)
    }
    let secure = SecureMessagingChannel(wrapping: channel, sessionKeys: established.keys)
    let operations = CardOperations(channel: secure, openedWith: role, plainChannel: channel)
    // PIN 2's service is DF.ESIGN and the PUK's is a reset that selects
    // what it needs, both from the main file where PACE leaves the card;
    // PIN 1's is the application.
    guard role != .pin1 || (try? operations.selectFineidApplication()) != nil else {
      return .refused(.failed, plain)
    }
    return .opened(operations)
  }

  /// One PACE run with `pin`, or ``ChannelEntryRefused`` for an entry its
  /// credential's type does not accept.
  private static func establishedChannel(
    over channel: any CardChannel,
    pin: ChannelPin
  ) throws -> (CredentialRole, PaceEstablishment.Established) {
    let establishment = PaceEstablishment(channel: channel)
    switch pin {
    case .pin1(let digits):
      guard let credential = Pin1(digits: digits) else { throw ChannelEntryRefused() }
      return (
        .pin1,
        try establishment.establish(
          with: PacePassword(pin1: credential.consumeForSingleTransmission()))
      )

    case .pin2(let digits):
      guard let credential = Pin2(digits: digits) else { throw ChannelEntryRefused() }
      return (
        .pin2,
        try establishment.establish(
          with: PacePassword(pin2: credential.consumeForSingleTransmission()))
      )

    case .puk(let digits):
      guard let credential = Puk(digits: digits) else { throw ChannelEntryRefused() }
      return (
        .puk,
        try establishment.establish(
          with: PacePassword(puk: credential.consumeForSingleTransmission()))
      )
    }
  }

  /// What a failed PACE run with a credential comes to.
  private static func paceRefusal(_ error: any Error) -> Outcome {
    switch error {
    case is ChannelEntryRefused:
      .invalidEntry

    case PaceEstablishment.Failure.credentialBlocked:
      .pinBlocked

    case PaceEstablishment.Failure.retryFloorRefused(let verdict, _):
      .floorRefused(verdict)

    case PaceEstablishment.Failure.passwordDeactivated:
      .invalidated

    case PaceEstablishment.Failure.wrongPin(let remaining):
      remaining.isBlocked ? .pinBlocked : .rejected(remaining: remaining)

    default:
      .failed
    }
  }
}
