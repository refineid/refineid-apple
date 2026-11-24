// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Foundation

/// One captured reading of reader, card, and credential state.
///
/// Captured on demand (manual or on-appear refresh; never polling, per
/// the release plan) inside one exclusive card session that is ended
/// before the snapshot returns.
internal struct CardStatusSnapshot: Equatable, Sendable {
  /// Why a capture could not produce card state.
  internal enum CaptureFailure: Equatable, Sendable {
    /// The card answered, but not readably.
    case cardUnreadable

    /// TKSmartCardSlotManager is unavailable on this device.
    case serviceUnavailable

    /// The exclusive session could not begin (contention or teardown).
    case sessionUnavailable
  }

  /// What the card slot held at capture time.
  internal enum CardState: Equatable, Sendable {
    /// Something failed; the typed reason is displayable.
    case failed(CaptureFailure)

    /// No card is present in the reader.
    case noCard

    /// A supported card, what it calls itself when it says, and its
    /// counter-safe probe report.
    case supported(CredentialProbeReport, name: String?)

    /// An identity card reached over a contactless interface, whose
    /// application stays sealed until PACE has run.
    ///
    /// Distinct from `unsupported`, which it used to be reported as: the
    /// card is a perfectly good one and the driver signs with it, it
    /// simply will not answer a plain SELECT. Saying "not a supported
    /// identity card" about a card the same app is signing with sends
    /// the holder looking for a different card.
    case sealed

    /// A card without the FINEID application.
    case unsupported
  }

  /// Carries the non-Sendable card into the background queue closure; the
  /// card is only touched on that one queue, serially.
  private final class UncheckedCard: @unchecked Sendable {
    let card: TKSmartCard

    init(_ card: TKSmartCard) {
      self.card = card
    }
  }

  /// The reader's name, or nil when no reader is attached.
  internal let readerName: String?

  /// The card state behind that reader.
  internal let card: CardState

  /// What the card's answer to reset says it is, when the table knows.
  ///
  /// Read from the slot rather than from the card: it costs no command,
  /// it works on an interface that answers nothing else until PACE has
  /// run, and it is the same on both interfaces of one card.
  internal let cardType: CardTypeIdentification?

  /// True when the smart-card extension has a live published token for
  /// Safari to enumerate.
  ///
  /// This deliberately does not query the token keychain. Enumerating
  /// token identities is an active operation on iOS: it can ask the
  /// extension to create a token and present the NFC reader sheet merely
  /// because this status screen appeared.
  internal let safariIdentityPresent: Bool

  /// Whether ctkd lists an identity token owned by this app.
  ///
  /// Advisory: read through a watcher built for the question, whose
  /// listing can lag its connection. The login row does not use this
  /// - it reads the long-lived watcher the login model owns.
  internal static func publishesAnIdentity() -> Bool {
    // Every token configuration is listed as a token, so the credential
    // entry the app itself writes and a displaced remote-card
    // registration must both be excluded -- each is listed with no card
    // present, and counting either reported "Ready" from nothing but
    // stored configuration.
    let credentialEntries =
      CardTokenNamespace.tokenPrefix + DriverConfiguredCredentials.configurationInstanceID
    return TKTokenWatcher().tokenIDs.contains { identifier in
      CardTokenNamespace.owns(tokenIdentifier: identifier)
        && !identifier.hasPrefix(credentialEntries)
        && !CardTokenNamespace.isDisplacedRemoteCardToken(tokenIdentifier: identifier)
    }
  }

  /// Captures a fresh snapshot: discovers the first slot, then runs one
  /// exclusive card session on a background queue (the card I/O is
  /// synchronous and blocking, so it must not stall Swift concurrency).
  internal static func capture() async -> Self {
    let tokenPresent = Self.publishesAnIdentity()
    guard let manager = TKSmartCardSlotManager.default else {
      return Self(
        readerName: nil,
        card: .failed(.serviceUnavailable),
        cardType: nil,
        safariIdentityPresent: tokenPresent
      )
    }
    guard let slotName = await CardSlotSearch.nameToReportOn(in: manager) else {
      return Self(
        readerName: nil, card: .noCard, cardType: nil, safariIdentityPresent: tokenPresent)
    }
    guard
      let slot = await manager.getSlot(withName: slotName),
      let smartCard = slot.makeSmartCard()
    else {
      return Self(
        readerName: slotName,
        card: .noCard,
        cardType: nil,
        safariIdentityPresent: tokenPresent
      )
    }
    let answerToReset = slot.atr?.bytes
    let cardState = await readCardOffMainThread(smartCard)
    return Self(
      readerName: slotName,
      card: cardState,
      cardType: answerToReset.flatMap(CardTypeIdentification.identify(answerToReset:)),
      safariIdentityPresent: tokenPresent
    )
  }

  /// Runs the synchronous, blocking card session on a background GCD
  /// queue and bridges the result back - never on the cooperative pool.
  private static func readCardOffMainThread(_ smartCard: TKSmartCard) async -> CardState {
    let boxed = UncheckedCard(smartCard)
    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        continuation.resume(returning: readCard(boxed.card))
      }
    }
  }

  /// Opens one exclusive session against the card and classifies it.
  private static func readCard(_ smartCard: TKSmartCard) -> CardState {
    do {
      return try SmartCardChannel(smartCard).withSession { channel in
        let operations = CardOperations(channel: channel)
        do {
          try operations.selectCardApplication()
        } catch CardOperationError.selectRejected(.securityNotSatisfied) {
          // The contactless answer, and the only one that means "ask me
          // again inside a secure channel". Probing further would cost a
          // PACE handshake on every refresh, for counters the holder can
          // read on the contact interface.
          return .sealed
        } catch CardOperationError.selectRejected {
          return .unsupported
        }
        let report: CredentialProbeReport
        do {
          report = try operations.probeCredentials()
        } catch let error where CardOperationError.requiresCanPace(error) {
          return .sealed
        }
        let sealedStatus = RetryProbeOutcome.other(StatusWord.securityNotSatisfied.encoded)
        if report.pin1 == sealedStatus
          || report.pin2 == sealedStatus
          || report.puk == sealedStatus
        {
          return .sealed
        }
        // Best effort, and after the counters: a card that will not name
        // itself is still a card, and this must not cost the reading
        // that matters.
        return .supported(report, name: try? operations.readTokenDescription())
      }
    } catch CardOperationError.sessionUnavailable {
      return .failed(.sessionUnavailable)
    } catch {
      return .failed(.cardUnreadable)
    }
  }
}
