// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Foundation

/// CryptoTokenKit entry point. `com.apple.ctk.driver-class` in
/// Config/TokenExtension-Info.plist names this class; the system
/// instantiates it when a smart card is inserted and asks the delegate to
/// create a token.
///
/// The two transports are minted differently, and the slot name is the
/// only thing there is to tell them apart before any card I/O. A contact
/// slot is read: the token reads the card's authentication certificate
/// and publishes the identity. A contactless slot is NOT read - it is
/// materialized from what the app stored while priming the card, because
/// that interface answers nothing before PACE and the system owns the
/// slot for barely two seconds. A card without the FINEID application,
/// without a readable auth certificate, without a prime, or with an
/// unsupported key profile is refused with a typed error - refusal is
/// safe: the system treats the card as not handled by this driver.
///
/// Provenance: the slot classification and the primed mint are the donor
/// `platform/apple/RefineIDTokenExtension/TokenDriver.swift`, whose
/// contactless branch was proven on device.
internal final class TokenDriver: TKSmartCardTokenDriver, TKSmartCardTokenDriverDelegate {
  /// How many times the mint looks for a prime before giving up.
  private static let primeWaitAttempts = 20

  /// How long the mint waits between looks for a prime.
  private static let primeWaitInterval: TimeInterval = 0.25

  /// How long to wait before the one retry a lost link earns.
  private static let retryInterval: TimeInterval = 0.15

  override internal init() {
    super.init()
    delegate = self
  }

  /// Reads the prime, allowing briefly for one being written right now.
  ///
  /// The first hold of a new card is a race the mint would otherwise
  /// always lose. The prime now happens in the SAME field as the mint:
  /// `ctkd` asks for a token the moment the card enters the slot, while
  /// the app is still running PACE and reading the certificate that
  /// becomes the prime -- so the first lookup finds nothing, and on a
  /// plain miss nothing ever asks again, leaving no token to register.
  ///
  /// Waiting a little converts that race into a hit. The wait is short
  /// and bounded because a card that was genuinely never primed must
  /// still fail rather than hold the field indefinitely. The five-second
  /// ceiling comes from a clean iPhone measurement: PACE plus the reads
  /// needed by the prime reached the store about 3.6 seconds after the
  /// mint began, before the bundled-issuer match removed about 0.7
  /// seconds of that. An already-primed card hits on the first read and
  /// waits not at all.
  private static func awaitPrime(
    lookupID: PrimeLookupIdentifier
  ) -> PrimeStore.ContactlessMatch? {
    for attempt in 1...primeWaitAttempts {
      if let match = PrimeStore.readContactless(lookupID: lookupID) {
        if attempt > 1 {
          TokenLog.trace("mintFromPrime: prime arrived on attempt \(attempt)")
        }
        return match
      }
      Thread.sleep(forTimeInterval: primeWaitInterval)
    }
    return nil
  }

  /// Mints from the card in the reader, once more if the first attempt
  /// died on the link rather than on the card's answer.
  ///
  /// A refused command is the card speaking and is reported as itself.
  /// A session that could not be opened, or a link that dropped part
  /// way, is not: the system asks for a token exactly once per
  /// insertion, so a lost attempt leaves no identity published and the
  /// holder with a card that does nothing until they pull it out and
  /// push it back in. One short retry turns that into a slower mint.
  private static func readerToken(
    smartCard: TKSmartCard,
    aid: Data?,
    tokenDriver: TKSmartCardTokenDriver
  ) throws -> TKSmartCardToken {
    do {
      return try readerTokenOnce(smartCard: smartCard, aid: aid, tokenDriver: tokenDriver)
    } catch let failure where isTransport(failure) {
      TokenLog.info("createToken: transport failed (\(failure)); one retry")
      Thread.sleep(forTimeInterval: retryInterval)
      return try readerTokenOnce(smartCard: smartCard, aid: aid, tokenDriver: tokenDriver)
    }
  }

  /// Converts the card's semantic activation result into an empty
  /// token.
  ///
  /// Transport failures still escape so the existing retry and
  /// CryptoTokenKit recovery paths retain their meaning.
  private static func readerTokenOnce(
    smartCard: TKSmartCard,
    aid: Data?,
    tokenDriver: TKSmartCardTokenDriver
  ) throws -> TKSmartCardToken {
    do {
      return try Token(smartCard: smartCard, aid: aid, tokenDriver: tokenDriver)
    } catch TokenError.activationRequired {
      TokenLog.notice("createToken: publishing activation-required state")
      return ActivationRequiredToken(
        smartCard: smartCard,
        aid: aid,
        tokenDriver: tokenDriver
      )
    }
  }

  /// Whether a failure is the link rather than the card's answer.
  private static func isTransport(_ failure: any Error) -> Bool {
    if case CardOperationError.sessionUnavailable = failure { return true }
    let error = failure as NSError
    guard error.domain == TKErrorDomain else { return false }
    return error.code == TKError.Code.communicationError.rawValue
      || error.code == TKError.Code.tokenNotFound.rawValue
  }

  /// How long something started at `instant` has taken, in milliseconds.
  private static func elapsed(since instant: ContinuousClock.Instant) -> String {
    TraceTiming.milliseconds(instant.duration(to: ContinuousClock.now))
  }

  internal func tokenDriver(
    _ driver: TKSmartCardTokenDriver,
    createTokenFor smartCard: TKSmartCard,
    aid: Data?
  ) throws -> TKSmartCardToken {
    // CryptoTokenKit does not name the client. Mail listing identities
    // and Safari signing both arrive here the same way. A registered
    // contactless token is minted by opening the NFC slot, which is
    // the Ready to Scan sheet; this callback cannot refuse Mail.
    // The slot name is all there is to classify by before any card I/O.
    let transport = CardTransport.transport(forSlotNamed: smartCard.slot.name)
    let started = ContinuousClock.now
    TokenLog.info("createToken called: aid=\(aid?.count ?? -1) B via \(transport.rawValue)")
    do {
      // Transport selection is automatic. CryptoTokenKit calls this
      // driver only for a slot that exists, so an attached reader or the
      // phone's active NFC slot is, by definition, available for use.
      let token: TKSmartCardToken =
        switch transport {
        case .nearField:
          try mintFromPrime(smartCard: smartCard, aid: aid, tokenDriver: driver)

        case .reader:
          try Self.readerToken(smartCard: smartCard, aid: aid, tokenDriver: driver)
        }
      TokenLog.info(
        "createToken succeeded ms=\(Self.elapsed(since: started))"
      )
      return token
    } catch let error as TokenError {
      TokenLog.error(
        "createToken failed (TokenError): \(error) ms=\(Self.elapsed(since: started))"
      )
      throw error.asTKError
    } catch {
      TokenLog.error(
        "createToken failed (other): \(error) ms=\(Self.elapsed(since: started))"
      )
      throw error
    }
  }

  /// Materializes the contactless token from the prime store without
  /// touching the card.
  ///
  /// Both halves were bought with measured failures. The mint does NO
  /// card I/O: the system owns this slot, and a read here disrupts the
  /// session it manages - the slot goes missing about a second later and
  /// the identity never reaches Safari. The one-time registration field
  /// publishes metadata and deliberately does not take a card session.
  /// A later signing field takes the session at the end: the minting slot
  /// ends about two seconds from there, and a `beginSession` issued when
  /// the signature arrives fails with `TKError -7`.
  ///
  /// The card is live in the slot for all of this, which is the app's
  /// side of the contract: `registerSmartCard` accepts only a token
  /// created for a live slot, so a field to hold is exactly what this
  /// path can assume.
  private func mintFromPrime(
    smartCard: TKSmartCard,
    aid: Data?,
    tokenDriver: TKSmartCardTokenDriver
  ) throws -> Token {
    // Each of the three is a different fault wearing the same error, and
    // the difference is the whole diagnosis: no ATR means the slot never
    // identified a card, no identifier means the ATR was empty, and no
    // prime means this card family has no active prime on this device.
    guard let answerToReset = smartCard.slot.atr?.bytes else {
      TokenLog.error("mintFromPrime: slot reports no answer to reset")
      throw TokenError.primeMissing
    }
    guard let lookupID = PrimeLookupIdentifier(answerToReset: answerToReset) else {
      TokenLog.error("mintFromPrime: atr=\(answerToReset.count)B names no card")
      throw TokenError.primeMissing
    }
    guard let match = Self.awaitPrime(lookupID: lookupID) else {
      TokenLog.error(
        "mintFromPrime: prime MISS for \(lookupID.value), "
          + "\(PrimeStore.storedCount()) prime(s) stored"
      )
      throw TokenError.primeMissing
    }
    guard
      let serialText = match.identity.tokenSerial,
      let serial = TokenSerial(value: serialText),
      let instanceID = CardInstanceIdentifier(tokenSerial: serial)
    else {
      TokenLog.error("mintFromPrime: prime has no supported printed card serial")
      throw TokenError.primeMissing
    }
    // Recorded rather than written: this is inside the two seconds the
    // system gives the mint, and the line is written out by whichever
    // `createToken` outcome line follows it.
    TokenLog.trace(
      "mintFromPrime: prime HIT "
        + "leaf=\(match.identity.certDER.count)B "
        + "issuer=\(match.identity.issuerDER?.count ?? -1)B "
        + "registration=\(match.isRegistrationField)"
    )
    let isPendingSign = PendingSigningState.shared.isPendingSign
    let needsSigningField = resolveSigningNeed(
      instanceID: instanceID,
      isRegistrationField: match.isRegistrationField,
      isPendingSign: isPendingSign
    )
    TokenLog.trace(
      "mintFromPrime: signing field needed=\(needsSigningField) (pendingSign=\(isPendingSign))"
    )
    return try Token(
      primedSmartCard: smartCard,
      aid: aid,
      tokenDriver: tokenDriver,
      instanceID: instanceID,
      primed: match.identity,
      shouldHoldSession: needsSigningField,
      isPendingSign: isPendingSign
    )
  }

  private func resolveSigningNeed(
    instanceID: CardInstanceIdentifier,
    isRegistrationField: Bool,
    isPendingSign: Bool
  ) -> Bool {
    let experimentEnabled = OnDemandPinExperiment.isEnabled
    let pinAvailable =
      experimentEnabled
      && (CardCredentialStore.contents().hasPin1
        || TransientCandidatePin1.shared.hasPending(for: instanceID)
        || VolatileAcceptedPin1.shared.hasPin(for: instanceID))
    return isPendingSign
      || OnDemandPinExperiment.needsSigningField(
        isRegistrationField: isRegistrationField,
        experimentEnabled: experimentEnabled,
        pinAvailable: pinAvailable
      )
  }
}
