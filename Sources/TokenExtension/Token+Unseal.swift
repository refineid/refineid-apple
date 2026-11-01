// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Foundation

/// The card read behind a reader-slot mint: SELECT, unseal when the
/// card asks to be, and the certificate pair.
///
/// Split from `Token` for length alone; this is the half that talks to
/// the card before a token exists.
extension Token {
  /// One number's PACE attempt and what became of it.
  private enum PaceAttempt {
    case minted(PublishedIdentity, CardAccessNumber)
    case refused(any Error)
    case transportDead(any Error)
  }

  /// Reads the leaf and (best-effort) issuer certificates in one
  /// exclusive card session, unsealing the card first if it asks to be.
  ///
  /// The card is asked rather than assumed. A slot name says which
  /// reader answered, not which interface of it the card is on: this
  /// reader publishes its contact, contactless and SAM interfaces under
  /// one name that differs only by a trailing index, and nothing in the
  /// name says which index is the antenna. What does distinguish them is
  /// the card's own answer. A contactless citizen card refuses SELECT of
  /// the PKCS#15 application with `6982` until PACE with its card access
  /// number has run. A contactless organization card answers `6985`, to
  /// the select or to the reads after it, until PACE with a PIN has run
  /// (FINEID S1 v4.0, organizational cards, section 2.1); it publishes
  /// the identity its contact read left in ``OrganizationPrimeStore``,
  /// and asks for the card slot when there is none. A contact card simply
  /// answers, and an organization card read there leaves that prime.
  ///
  /// Only those two status words take another path. Any other failure is
  /// reported as itself, because a card that is missing, mute or
  /// something else entirely is not a card that wants a password, and
  /// running PACE at it would replace a legible fault with a wrong one.
  internal static func readIdentity(
    from smartCard: TKSmartCard
  ) throws -> (identity: PublishedIdentity, unsealing: CardUnsealing) {
    TokenLog.info("readIdentity: opening session")
    let answerToReset = smartCard.slot.atr?.bytes
    return try SmartCardChannel(smartCard, waits: .readerMint).withSession { channel in
      do {
        TokenLog.info("readIdentity: selecting application")
        try CardOperations(channel: channel).selectFineidApplication()
      } catch CardOperationError.selectRejected(.securityNotSatisfied) {
        TokenLog.info("readIdentity: application is sealed; unsealing")
        CardCredentialStore.recordCardAsk(.cardAccessNumber)
        let (identity, accessNumber) = try Self.unsealed(
          over: channel, answerToReset: answerToReset)
        return (identity, .cardAccessNumber(accessNumber))
      } catch CardOperationError.selectRejected(.conditionsNotSatisfied) {
        return try Self.organizationIdentity(answerToReset: answerToReset)
      }
      let operations = CardOperations(channel: channel)
      let identity: PublishedIdentity
      do {
        identity = try Self.certificates(read: operations)
      } catch let failure where CardOperationError.refusesBeforePace(failure) {
        return try Self.organizationIdentity(answerToReset: answerToReset)
      }
      Self.primeOrganizationCard(identity, operations: operations, answerToReset: answerToReset)
      return (identity, .plain)
    }
  }

  /// The identity of an organization card on the antenna, from the prime
  /// its contact read left; without one, the card slot is asked for.
  private static func organizationIdentity(
    answerToReset: Data?
  ) throws -> (identity: PublishedIdentity, unsealing: CardUnsealing) {
    guard
      let answerToReset,
      let prime = OrganizationPrimeStore.read(answerToReset: answerToReset)
    else {
      TokenLog.info("readIdentity: card refuses reads on this interface; asks for the card slot")
      CardCredentialStore.recordCardAsk(.cardSlot)
      throw CardOperationError.selectRejected(.conditionsNotSatisfied)
    }
    TokenLog.info("readIdentity: organization card on the antenna; publishing its prime")
    CardCredentialStore.clearCardAsk()
    let identity = PublishedIdentity(
      leafDER: prime.certificateDER,
      issuerDER: prime.issuerDER,
      signLeafDER: prime.signatureCertificateDER,
      chipSerial: prime.chipSerial
    )
    return (identity, .organizationPin)
  }

  /// Keeps an organization card's identity, read in a contact slot, for
  /// the card's arrival on an antenna.
  ///
  /// The numbering decides: the organization card answers its own
  /// security-data-object references (FINEID S4-2 v4.0 section 4.2). The
  /// probe is counter-safe and usually already answered by the activation
  /// check. Best effort: a prime that is not written leaves the antenna
  /// asking for the card slot, as before.
  private static func primeOrganizationCard(
    _ identity: PublishedIdentity,
    operations: CardOperations,
    answerToReset: Data?
  ) {
    guard
      let answerToReset,
      !AnswerToReset.indicatesContactlessInterface(bytes: answerToReset),
      (try? operations.resolveCredentialReferences()) == .organization,
      let prime = OrganizationPrime(
        certificate: identity.leafDER,
        issuer: identity.issuerDER,
        signatureCertificate: identity.signLeafDER,
        chipSerial: identity.chipSerial
      )
    else {
      return
    }
    let stored = OrganizationPrimeStore.store(prime, answerToReset: answerToReset)
    TokenLog.info("readIdentity: organization card primed for the antenna stored=\(stored)")
  }

  /// Runs PACE over an already-open channel and reads through it.
  ///
  /// This is the priming flow the app runs on the phone, in the
  /// extension and without the deadline. A reader powers the card
  /// continuously, so there is no field to lose and nothing to store
  /// ahead of time: the certificate is read live, exactly as the contact
  /// path reads it, and the identity is published from what the card
  /// just said.
  ///
  /// The card access number is the one the holder entered. Absent, this
  /// stops here with a typed refusal -- a sealed card and no number is
  /// setup that has not been done, not a fault to keep retrying at.
  private static func unsealed(
    over channel: SmartCardChannel,
    answerToReset: Data?
  ) throws -> (identity: PublishedIdentity, accessNumber: CardAccessNumber) {
    // Every stored number, active offer first: a card answers with no
    // individual identifier before PACE, so one number cannot be
    // selected for it: the first is tried, and a refusal wipes them
    // all.
    let candidates = CardCredentialStore.cardAccessNumberCandidates()
    guard !candidates.isEmpty else {
      // The status separates the two faults that look identical here:
      // nothing stored is setup not done, while a refusal is this
      // process being unable to read what the app wrote.
      TokenLog.error(
        "readIdentity: card is sealed and no card access number is readable "
          + "(status=\(CardCredentialStore.cardAccessNumberReadStatus()); "
          + "offer: \(CardCanOffer.missDescription()))"
      )
      throw TokenError.primeMissing
    }
    // The latch, before any card time is spent: a failed PACE tears the
    // field, the card re-arrives, and the system asks again with
    // nothing changed. Numbers this card just refused are skipped; a
    // fresh number is what earns the card a fresh attempt.
    let fresh = Self.freshCandidates(candidates, answerToReset: answerToReset)
    guard !fresh.isEmpty else {
      TokenLog.info("readIdentity: these numbers were just refused by this card; not retrying yet")
      CardCredentialStore.recordOfferedNumberRefusal()
      throw TokenError.unsealAlreadyRefused
    }
    // One try: the first CAN the card refuses wipes them all.
    guard let candidate = fresh.first else { throw TokenError.unsealAlreadyRefused }
    switch Self.paceAttempt(candidate: candidate, index: 0, total: 1, channel: channel) {
    case .minted(let identity, let accessNumber):
      return (identity, accessNumber)

    case .refused(let failure):
      // The card would not open with this CAN: every CAN in memory
      // goes, and the holder types the one printed on the card.
      CardCredentialStore.forgetEveryCardAccessNumber()
      CardCredentialStore.recordOfferedNumberRefusal()
      TokenLog.error("readIdentity: card refused the CAN; every CAN in memory forgotten")
      throw failure

    case .transportDead(let error):
      // A transport death is not a refusal of this number: the card
      // stopped answering. Latch and report; nothing is forgotten.
      RefusedUnseal.shared.record(
        fingerprint: CardCredentialStore.fingerprint(canDigits: candidate.digits),
        answerToReset: answerToReset)
      TokenLog.error("readIdentity: transport failed (\(error)); latched against immediate retry")
      throw error
    }
  }

  /// Runs PACE for one candidate and reads through it on success.
  ///
  /// A mint remembers its number under the card's serial, so the next
  /// arrival of the same card needs no typing and no retrying.
  private static func paceAttempt(
    candidate: CardCanOffer.Candidate,
    index: Int,
    total: Int,
    channel: SmartCardChannel
  ) -> PaceAttempt {
    let started = ContinuousClock.now
    // PACE starts at main-file level, where its read of EF.CardAccess
    // leaves the card: the card refuses MSE:Set AT with 6985 anywhere
    // else.
    do {
      let keys = try PaceEstablishment(channel: channel)
        .establish(with: PacePassword(cardAccessNumber: candidate.number)).keys
      RefusedUnseal.shared.clear()
      CardCredentialStore.clearOfferedNumberRefusal()
      let secure = SecureMessagingChannel(wrapping: channel, sessionKeys: keys)
      TokenLog.info(
        "readIdentity: PACE ok, candidate \(index + 1)/\(total) "
          + "ms=\(Self.elapsed(since: started))")
      let operations = CardOperations(channel: secure)
      try operations.selectFineidApplication()
      let identity = try Self.certificates(read: operations)
      CardCredentialStore.rememberCan(
        digits: candidate.digits, chipSerial: identity.chipSerial)
      return .minted(identity, candidate.number)
    } catch let failure as PaceEstablishment.Failure {
      TokenLog.error(
        "readIdentity: candidate \(index + 1)/\(total) refused (\(failure))")
      return .refused(failure)
    } catch {
      return .transportDead(error)
    }
  }

  /// Numbers this card has not just refused.
  private static func freshCandidates(
    _ candidates: [CardCanOffer.Candidate],
    answerToReset: Data?
  ) -> [CardCanOffer.Candidate] {
    candidates.filter { candidate in
      !RefusedUnseal.shared.isRefused(
        fingerprint: CardCredentialStore.fingerprint(canDigits: candidate.digits),
        answerToReset: answerToReset)
    }
  }

  /// Reads the leaf, serial, and the issuer if the card offers one.
  ///
  /// The serial is read before the issuer because the leaf read leaves the
  /// PKCS#15 application selected, while the issuer read navigates to the
  /// main file.
  private static func certificates(
    read operations: CardOperations
  ) throws -> PublishedIdentity {
    TokenLog.info("readIdentity: reading leaf EF.4331")
    let leaf = try operations.readCertificate(.authentication)
    try Self.requireActivatedCard(leaf, operations: operations)
    TokenLog.info("readIdentity: leaf \(leaf.count) bytes; reading chip serial")
    let serial = try operations.readChipSerial()
    TokenLog.info("readIdentity: chip serial read; resolving issuer")
    let issuer = TrustRootsCache.shared.issuer(
      for: leaf,
      cardIssuer: { try? operations.readCertificate(.issuing) },
      cardRoot: { try? operations.readCertificate(.root) }
    )
    TokenLog.info("readIdentity: issuer \(issuer?.count ?? -1) bytes")
    // The qualified leaf is optional and therefore read LAST. A card
    // that lacks the slot answers the select with `6A82`, and a
    // refused select leaves a different file current - so attempting
    // this any earlier can make the reads that follow it fail, which
    // is a mint lost for an identity that was never required.
    let signLeaf =
      (try? operations.readCertificate(.qualifiedSignature))
      ?? (try? operations.readCertificate(.secondQualifiedSignature))
    reportInventory(read: operations)
    TokenLog.info("readIdentity: sign leaf \(signLeaf?.count ?? -1) bytes")
    return PublishedIdentity(
      leafDER: leaf,
      issuerDER: issuer,
      signLeafDER: signLeaf,
      chipSerial: serial
    )
  }

  /// Refuses token publication while any PIN awaits activation.
  ///
  /// Every probe is counter-safe. A card without an activation decision
  /// publishes.
  private static func requireActivatedCard(
    _ authenticationCertificate: Data,
    operations: CardOperations
  ) throws {
    guard
      let activation = operations.activationClassification(
        authenticationCertificate: authenticationCertificate)
    else {
      return
    }
    let needs = operations.activationNeeds(scheme: activation.scheme)
    guard !needs.any else {
      TokenLog.notice(
        "readIdentity: activation required pin1=\(needs.pin1) pin2=\(needs.pin2)"
      )
      throw TokenError.activationRequired
    }
  }

  /// Records what the card's own directories say it carries.
  ///
  /// Nothing is published from this yet: it is the inventory the fixed
  /// slots cannot see, read to learn each key's reference before any
  /// identity is built from it.
  private static func reportInventory(read operations: CardOperations) {
    let entries: [Pkcs15Inventory.Entry]
    do {
      entries = try operations.readPkcs15Inventory()
    } catch {
      TokenLog.info("readIdentity: PKCS#15 inventory unreadable (\(error))")
      return
    }
    TokenLog.info("readIdentity: PKCS#15 inventory lists \(entries.count) certificates")
    for entry in entries {
      let identifierHex = entry.certificate.identifier
        .map { byte in
          String(format: "%02X", byte)
        }
        .joined()
      let keyReferenceHex =
        entry.key?.keyReference.map { byte in
          String(format: "%02X", byte)
        } ?? "none"
      TokenLog.info(
        "readIdentity: inventory entry file=\(entry.certificate.file) "
          + "id=\(identifierHex) "
          + "key=\(entry.key != nil) "
          + "keyReference=\(keyReferenceHex)"
      )
    }
  }

  /// How long something started at `instant` has taken, in milliseconds.
  private static func elapsed(since instant: ContinuousClock.Instant) -> String {
    TraceTiming.milliseconds(instant.duration(to: ContinuousClock.now))
  }
}
