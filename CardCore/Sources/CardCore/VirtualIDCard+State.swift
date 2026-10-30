// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// What the simulated card and its device hold: the credentials, the
/// certificates, and the snapshot that pairs them.
extension VirtualIDCard {
  /// How the simulated device reaches the card.
  public enum Transport: String, CaseIterable, Sendable {
    case nearField = "nearField"
    case reader = "reader"
  }

  /// The card generation, which decides what the activation entry is.
  ///
  /// Legacy cards accept their PUK as the activation code; current cards
  /// ship a preset activation PIN.
  public enum Generation: String, CaseIterable, Sendable {
    case activationCodeIsPuk = "activationCodeIsPuk"
    case presetActivationPIN = "presetActivationPIN"
  }

  /// The condition of one on-card certificate as reads report it.
  public enum CertificateState: String, CaseIterable, Sendable {
    case valid = "valid"
    case expired = "expired"
    case revoked = "revoked"
    case unreadable = "unreadable"
    case missing = "missing"
  }

  /// One PIN or PUK as stored on the simulated card.
  public struct CredentialState: Equatable, Sendable {
    /// The digits the card currently accepts.
    public var value: String
    /// Attempts left before the credential blocks.
    public var attemptsRemaining: UInt8
    /// True while the credential still holds its factory value.
    public var isFactoryValue: Bool

    /// Creates a credential with the given digits and retry allowance.
    public init(
      value: String,
      attemptsRemaining: UInt8,
      isFactoryValue: Bool = false
    ) {
      self.value = value
      self.attemptsRemaining = attemptsRemaining
      self.isFactoryValue = isFactoryValue
    }
  }

  /// The card-side state: what a physical card itself stores and reports.
  public struct CardState: Equatable, Sendable {
    /// The transport this card connects over.
    public var transport: Transport
    /// True when a contact reader is attached.
    public var readerConnected: Bool
    /// True while the card is present on its transport.
    public var cardPresent: Bool
    /// The activation scheme generation of this card.
    public var generation: Generation
    /// The six-digit CAN printed on the card.
    public var cardAccessNumber: String
    /// The entry the card accepts when activating factory credentials.
    public var activationEntry: String
    /// PIN 1, the authentication credential.
    public var pin1: CredentialState
    /// PIN 2, the qualified-signature credential.
    public var pin2: CredentialState
    /// The PUK that recovers blocked PINs.
    public var puk: CredentialState
    /// The holder's name as printed on the card.
    public var holderName: String
    /// The identifier that names the holder in electronic services.
    public var electronicClientIdentifier: String
    /// The serial the chip reports.
    public var chipSerial: ChipSerial
    /// The condition of the authentication certificate.
    public var authenticationCertificate: CertificateState
    /// The condition of the qualified signature certificate.
    public var signatureCertificate: CertificateState

    /// Creates a fully specified card state.
    public init(
      transport: Transport,
      readerConnected: Bool,
      cardPresent: Bool,
      generation: Generation,
      cardAccessNumber: String,
      activationEntry: String,
      pin1: CredentialState,
      pin2: CredentialState,
      puk: CredentialState,
      holderName: String,
      electronicClientIdentifier: String,
      chipSerial: ChipSerial,
      authenticationCertificate: CertificateState,
      signatureCertificate: CertificateState
    ) {
      self.transport = transport
      self.readerConnected = readerConnected
      self.cardPresent = cardPresent
      self.generation = generation
      self.cardAccessNumber = cardAccessNumber
      self.activationEntry = activationEntry
      self.pin1 = pin1
      self.pin2 = pin2
      self.puk = puk
      self.holderName = holderName
      self.electronicClientIdentifier = electronicClientIdentifier
      self.chipSerial = chipSerial
      self.authenticationCertificate = authenticationCertificate
      self.signatureCertificate = signatureCertificate
    }
  }

  /// What the simulated device remembers independently of the card.
  public struct DeviceState: Equatable, Sendable {
    /// The CAN saved on the device for future near-field connections.
    public var storedCardAccessNumber: String?
    /// The CAN in use on the currently open near-field connection.
    public var connectedCardAccessNumber: String?
    /// True once the device has cached the holder's identity.
    public var cachedIdentity: Bool
    /// True once the device has published the card as a token.
    public var tokenRegistered: Bool
    /// True while a signature authorization is in flight.
    public var pendingSigningRequest: Bool

    /// Creates device state; every field defaults to a fresh device.
    public init(
      storedCardAccessNumber: String? = nil,
      connectedCardAccessNumber: String? = nil,
      cachedIdentity: Bool = false,
      tokenRegistered: Bool = false,
      pendingSigningRequest: Bool = false
    ) {
      self.storedCardAccessNumber = storedCardAccessNumber
      self.connectedCardAccessNumber = connectedCardAccessNumber
      self.cachedIdentity = cachedIdentity
      self.tokenRegistered = tokenRegistered
      self.pendingSigningRequest = pendingSigningRequest
    }
  }

  /// One observable moment: card state, device state, and queued faults.
  public struct Snapshot: Equatable, Sendable {
    /// The card-side state.
    public var card: CardState
    /// The device-side state.
    public var device: DeviceState
    /// Transport faults waiting to fire, in queue order.
    public var faults: [Fault]

    /// Creates a snapshot, with no faults queued by default.
    public init(
      card: CardState,
      device: DeviceState,
      faults: [Fault] = []
    ) {
      self.card = card
      self.device = device
      self.faults = faults
    }
  }
}
