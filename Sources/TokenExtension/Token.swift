// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Foundation
import Security

/// The token instance for one inserted card.
///
/// At creation it reads the on-card authentication certificate through
/// CardCore, discovers the key profile, and publishes into the keychain
/// the leaf certificate, a sign-only key gated behind PIN1, and (when
/// present) the issuing-CA certificate - so Safari offers the identity
/// at a service's client-certificate request. Signing itself is the
/// session's responsibility.
internal final class Token: TKSmartCardToken, TKTokenDelegate {
  // MARK: Static Properties

  /// The auth certificate and its key share this keychain object ID.
  internal static let authObjectID = CardTokenNamespace.authKeyObjectID
  /// The qualified-signature certificate and key share this object ID.
  internal static let signObjectID = "sign"
  /// The published issuing-CA certificate's object ID (cert-only).
  internal static let issuerObjectID = CardTokenNamespace.issuerCertificateObjectID
  private static let tokenIDPrefixLength = 8

  // MARK: Properties

  /// The authentication key's profile, resolved from the leaf and used
  /// by the session to advertise and select signing algorithms.
  internal let keyProfile: CardKeyProfile

  /// The qualified key's profile; nil when the card offered none.
  ///
  /// Nil covers an absent slot and a contactless prime. Qualified signing
  /// keys are reserved for document signing and are never published as
  /// browser client authentication identities.
  internal let signKeyProfile: CardKeyProfile?

  /// The qualified leaf's public key, for the same fail-closed local
  /// verification the authentication key gets.
  internal let signLeafPublicKey: SecKey?

  /// The leaf's public key, used by the session to verify each raw card
  /// signature before returning it - a card that lost its loaded hash
  /// signs silently-wrong bytes with no error SW (S1 v4.2 §3.8.1.1), and
  /// the token must fail closed rather than feed the TLS stack garbage.
  ///
  /// On the contactless path this is also the cached form of the
  /// certificate the prime read: the leaf is public and unchanging, so
  /// the signature never spends its field re-reading EF.4331 to get it.
  internal let leafPublicKey: SecKey

  /// The card access number this card must be unsealed with; nil when the
  /// card answered in the clear.
  ///
  /// Never logged. Its presence, not the slot it arrived on, is what
  /// tells the session which card it is holding: with one, every verb
  /// travels inside a PACE channel; without one, the card is spoken to
  /// directly.
  ///
  /// A contactless card is sealed whichever antenna reaches it -- the
  /// phone's own or the one in a desk reader -- so this is set on both,
  /// and the two differ only in where the number came from. The phone
  /// takes it from the prime, because the system ends that slot about two
  /// seconds after the mint and there is no room to read anything. A
  /// reader holds its field indefinitely, so there the card is unsealed
  /// and read on the spot, and no prime is needed at all.
  internal let sealedAccessNumber: CardAccessNumber?

  /// How this card is reached, which decides what a signature may spend.
  internal let interface: CardInterface

  /// The card's token serial as the prime read it, contactless tokens
  /// only.
  ///
  /// Cached for the same reason as the certificate: it is public, it
  /// cannot change, and re-reading it costs more than the field has left
  /// - that read was measured dying part way through, which is a login
  /// lost for nothing.
  internal let primedSerial: TokenSerial?

  /// Stable public identity of the physical card represented by this token.
  ///
  /// This is also the revocation boundary: a confirmed CAN, PIN1, or PIN2
  /// rejection bankrupts this live token and its stored registration.
  internal let cardInstanceID: CardInstanceIdentifier

  /// Ephemeral identifier for diagnostic logging without printing card serials.
  internal let tokenID = "tok-" + UUID().uuidString.prefix(tokenIDPrefixLength)

  /// The card session taken at the mint and kept open for the signature.
  ///
  /// Empty on the contact path, which opens a session per operation.
  internal let heldSession = HeldCardSession()

  /// PIN1 this card accepted, kept only while this token is live.
  internal let acceptedPin1 = AcceptedPin1Memory()

  /// Releases the held session when the card leaves the slot.
  internal var slotStateObservation: NSKeyValueObservation?

  /// One-way lifetime state shared by every session of this token.
  private let revocationLock = NSLock()
  private var revoked = false

  // MARK: Computed Properties

  /// Whether a card-confirmed credential refusal has bankrupted this token.
  internal var isRevoked: Bool {
    revocationLock.lock()
    defer { revocationLock.unlock() }
    return revoked
  }

  // MARK: Lifecycle

  internal init(
    smartCard: TKSmartCard,
    aid: Data?,
    tokenDriver: TKSmartCardTokenDriver
  ) throws {
    let material = try Self.validatedReaderMaterial(from: smartCard)
    self.keyProfile = material.profile
    self.leafPublicKey = material.publicKey
    self.signKeyProfile = material.signProfile
    self.signLeafPublicKey = material.signPublicKey
    self.sealedAccessNumber = material.accessNumber
    // A card read here was read through a reader, whichever of its
    // interfaces answered: this initializer does card I/O, which the
    // phone's path cannot afford at all.
    self.interface = material.accessNumber == nil ? .contact : .steadyField
    self.primedSerial = nil
    self.cardInstanceID = material.instanceID
    super.init(
      smartCard: smartCard,
      aid: aid,
      instanceID: material.instanceID.value,
      tokenDriver: tokenDriver
    )
    delegate = self
    observeSlotState(of: smartCard)
    TokenLog.info(
      "Token.init(reader): id=\(tokenID) profile=\(String(describing: material.profile))"
    )
    try publish(
      material.identity,
      leaf: material.leaf,
      profile: material.profile,
      signLeaf: material.signLeaf,
      signProfile: material.signProfile
    )
  }

  /// Creates the token from a primed identity instead of from the card.
  ///
  /// The contactless interface seals the PKCS#15 application until PACE
  /// has run, so this cannot read the certificate the way the contact
  /// path does - and on the system-driven path it must not try at all:
  /// `ctkd` owns the slot, ends it about two seconds from here, and a
  /// read issued now was measured taking the slot away before the
  /// identity ever reached Safari. Everything needed is already in the
  /// prime the app stored - certificate, chain, serial and card access
  /// number, all read from this same card and none of them able to have
  /// changed since - so this mint does NO card I/O whatsoever and
  /// publishes exactly the items the contact path would.
  internal init(
    primedSmartCard smartCard: TKSmartCard,
    aid: Data?,
    tokenDriver: TKSmartCardTokenDriver,
    instanceID: CardInstanceIdentifier,
    primed: PrimedIdentity,
    shouldHoldSession: Bool
  ) throws {
    // Recorded, not written: this whole initializer runs inside the two
    // seconds the system gives the mint, and every line here is written
    // out by the `createToken` outcome that follows. Each refusal is
    // named, because they all leave the same error at the boundary and
    // the difference between them is the diagnosis.
    let material = try Self.validated(primed: primed, instanceID: instanceID)
    self.keyProfile = material.profile
    self.leafPublicKey = material.publicKey
    self.signKeyProfile = nil
    self.signLeafPublicKey = nil
    self.sealedAccessNumber = material.accessNumber
    self.interface = .fieldWithDeadline
    self.primedSerial = material.serial
    self.cardInstanceID = instanceID
    super.init(
      smartCard: smartCard,
      aid: aid,
      instanceID: instanceID.value,
      tokenDriver: tokenDriver
    )
    delegate = self
    TokenLog.info("Token.init(primed): id=\(tokenID)")
    if shouldHoldSession {
      observeSlotState(of: smartCard)
      holdSession(on: smartCard)
    }
    try publish(
      PublishedIdentity(
        leafDER: primed.certDER,
        issuerDER: primed.issuerDER,
        signLeafDER: nil,
        tokenSerial: material.serial
      ),
      leaf: material.leaf,
      profile: material.profile,
      signLeaf: nil,
      signProfile: nil
    )
    TokenLog.trace(
      "Token.init(primed): published, profile=\(String(describing: material.profile))")
  }

  /// Irreversibly disables this token instance and releases its card session.
  internal func revokeCurrentInstance() {
    revocationLock.lock()
    revoked = true
    revocationLock.unlock()
    acceptedPin1.clearAll()
    VolatileAcceptedPin1.shared.clear(for: cardInstanceID)
    TransientCandidatePin1.shared.clear(for: cardInstanceID)
    heldSession.release()
  }

  /// Gives back the held session when the token itself goes away.
  ///
  /// The slot observation covers the card leaving; this covers `ctkd`
  /// dropping the token for any other reason. A session left open on the
  /// phone's own antenna keeps the radio, and the next hold then meets
  /// the busy answer ``NearFieldCardSession`` has to retry through -
  /// about 2.5 seconds of the holder's time for nothing.
  deinit {
    TokenLog.info("Token.deinit: id=\(tokenID)")
    acceptedPin1.clearAll()
    heldSession.release()
    // Last chance to get the trace out of a process ctkd is dropping: a
    // token going away is often the only sign of what ended a login, and
    // anything still only recorded would go with it.
    TokenLog.flush()
  }
}
