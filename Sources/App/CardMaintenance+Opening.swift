// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// Opening the card for one operation: in the clear, or with PACE and the
/// card access number or the operation's PIN.
extension CardMaintenance {
  /// The PIN an operation spends, offered to open an organization card on
  /// an antenna: such a card opens its PACE channel with PIN 1 or PIN 2 in
  /// place of a card access number (FINEID S1 v4.0, organizational cards,
  /// section 2.1), and a completed PACE counts as that PIN verified.
  internal enum ChannelPin: Sendable {
    case pin1(String)
    case pin2(String)
  }

  /// What opens a sealed card for one operation.
  ///
  /// A citizen card on an antenna opens with its card access number; an
  /// organization card there opens with the PIN the operation spends, and
  /// `refused` answers the operation when the card refuses that PIN.
  internal struct CardOpener<Answer>: Sendable {
    /// The card access number offered, or nil for the one in memory.
    internal let cardAccessNumber: String?

    /// The PIN the operation spends, offered to an organization card.
    internal let channelPin: ChannelPin?

    /// The operation's answer to a refused PIN.
    internal let refused: (@Sendable (Outcome) -> Answer)?

    /// The card access number alone.
    internal static func cardAccessNumber(_ digits: String?) -> Self {
      Self(cardAccessNumber: digits, channelPin: nil, refused: nil)
    }

    /// The card access number, and `pin` for an organization card.
    internal static func pin(
      _ pin: ChannelPin,
      cardAccessNumber digits: String?,
      refused: @escaping @Sendable (Outcome) -> Answer
    ) -> Self {
      Self(cardAccessNumber: digits, channelPin: pin, refused: refused)
    }
  }

  /// What opening the card for an operation came to.
  internal enum Opening {
    /// The card answers through these operations.
    case opened(CardOperations)

    /// The card refused the offered PIN, at the floor or at the handshake.
    case refused(Outcome)

    /// No channel could be opened.
    case unavailable
  }

  /// What `work` answers on an opened card, what `refused` answers for a
  /// refused PIN, and nothing when no channel opened.
  internal static func answer<Answer>(
    _ opening: Opening,
    refused: ((Outcome) -> Answer)?,
    _ work: (CardOperations) -> Answer?
  ) -> Answer? {
    switch opening {
    case .opened(let operations):
      work(operations)

    case .refused(let outcome):
      refused?(outcome)

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
  /// PIN, to the select or to the reads after it, so on the contactless
  /// interface a select that succeeds is followed by one read to tell;
  /// without a PIN offered, such a card stays closed, since no card
  /// access number opens it.
  internal static func openedOperations<Answer>(
    over channel: SmartCardChannel,
    opener: CardOpener<Answer>
  ) -> Opening {
    let cardAccessNumber = opener.cardAccessNumber
    let channelPin = opener.channelPin
    let operations = CardOperations(channel: channel)
    do {
      try operations.selectFineidApplication()
      guard
        let channelPin,
        let answerToReset = channel.answerToReset,
        AnswerToReset.indicatesContactlessInterface(bytes: answerToReset)
      else {
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
    over channel: SmartCardChannel,
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

  /// PACE with the operation's PIN, the retry floor applied to the state
  /// MSE:Set AT reports before any try is spent.
  private static func pinOpenedOperations(
    over channel: SmartCardChannel,
    pin: ChannelPin
  ) -> Opening {
    let role: CredentialRole
    let established: PaceEstablishment.Established
    do {
      switch pin {
      case .pin1(let digits):
        guard let credential = Pin1(digits: digits) else { return .refused(.invalidEntry) }
        role = .pin1
        established = try PaceEstablishment(channel: channel)
          .establish(with: PacePassword(pin1: credential.consumeForSingleTransmission()))

      case .pin2(let digits):
        guard let credential = Pin2(digits: digits) else { return .refused(.invalidEntry) }
        role = .pin2
        established = try PaceEstablishment(channel: channel)
          .establish(with: PacePassword(pin2: credential.consumeForSingleTransmission()))
      }
    } catch PaceEstablishment.Failure.retryFloorRefused(let verdict, _) {
      return .refused(.floorRefused(verdict))
    } catch PaceEstablishment.Failure.passwordDeactivated {
      return .refused(.invalidated)
    } catch PaceEstablishment.Failure.wrongPin(let remaining) {
      return .refused(remaining.isBlocked ? .pinBlocked : .rejected(remaining: remaining))
    } catch {
      return .refused(.failed)
    }
    let secure = SecureMessagingChannel(wrapping: channel, sessionKeys: established.keys)
    let operations = CardOperations(channel: secure, openedWith: role)
    // PIN 2's service is DF.ESIGN, which the operation selects from the
    // main file where PACE leaves the card; PIN 1's is the application.
    guard role == .pin2 || (try? operations.selectFineidApplication()) != nil else {
      return .refused(.failed)
    }
    return .opened(operations)
  }
}
