// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The presets a virtual card starts from, and the transport faults a
/// scenario can queue against it.
extension VirtualIDCard {
  /// A preset snapshot the virtual card can start from or reset to.
  public enum Scenario: String, CaseIterable, Sendable {
    case factoryFreshNearField = "factory-fresh-nfc"
    case legacyFactoryFreshNearField = "legacy-factory-fresh-nfc"
    case partialActivationNearField = "partial-activation-nfc"
    case activatedNearField = "activated-nfc"
    case registeredNearField = "registered-nfc"
    case factoryFreshReader = "factory-fresh-reader"
    case activatedReader = "activated-reader"
    case pin1RecoveryReader = "pin1-recovery-reader"
    case pin2RecoveryReader = "pin2-recovery-reader"
    case pukRecoveryRefusedReader = "puk-recovery-refused-reader"
    case absent = "absent"

    /// Whether the scenario connects over the near-field transport.
    public var usesNearField: Bool {
      switch self {
      case .factoryFreshNearField,
        .legacyFactoryFreshNearField,
        .partialActivationNearField,
        .activatedNearField,
        .registeredNearField:
        true

      case .factoryFreshReader,
        .activatedReader,
        .pin1RecoveryReader,
        .pin2RecoveryReader,
        .pukRecoveryRefusedReader,
        .absent:
        false
      }
    }

    /// The card and device state this scenario begins with.
    public var snapshot: Snapshot {
      let accessNumber = "123456"
      let activationPIN = "1234567"
      let defaultPIN1 = "1234"
      let defaultPIN2 = "123456"
      let defaultPUK = "12345678"
      var card = CardState(
        transport: .nearField,
        readerConnected: false,
        cardPresent: true,
        generation: .presetActivationPIN,
        cardAccessNumber: accessNumber,
        activationEntry: activationPIN,
        pin1: CredentialState(
          value: defaultPIN1,
          attemptsRemaining: RetryCount.pristineAllowance),
        pin2: CredentialState(
          value: defaultPIN2,
          attemptsRemaining: RetryCount.pristineAllowance),
        puk: CredentialState(
          value: defaultPUK,
          attemptsRemaining: RetryCount.pristineAllowance),
        holderName: "DOE JANE",
        electronicClientIdentifier: "12345678N",
        chipSerialText: "XA1234567",
        authenticationCertificate: .valid,
        signatureCertificate: .valid)
      var device = DeviceState()

      switch self {
      case .factoryFreshNearField:
        card.pin1 = CredentialState(
          value: activationPIN,
          attemptsRemaining: RetryCount.pristineAllowance,
          isFactoryValue: true)
        card.pin2 = CredentialState(
          value: activationPIN,
          attemptsRemaining: RetryCount.pristineAllowance,
          isFactoryValue: true)

      case .legacyFactoryFreshNearField:
        card.generation = .activationCodeIsPuk
        card.activationEntry = defaultPUK
        card.pin1 = CredentialState(
          value: defaultPIN1,
          attemptsRemaining: 0,
          isFactoryValue: true)
        card.pin2 = CredentialState(
          value: defaultPIN2,
          attemptsRemaining: 0,
          isFactoryValue: true)

      case .partialActivationNearField:
        card.pin2 = CredentialState(
          value: activationPIN,
          attemptsRemaining: RetryCount.pristineAllowance,
          isFactoryValue: true)

      case .activatedNearField:
        break

      case .registeredNearField:
        device = DeviceState(
          storedCardAccessNumber: accessNumber,
          connectedCardAccessNumber: accessNumber,
          cachedIdentity: true,
          tokenRegistered: true)

      case .factoryFreshReader:
        card.transport = .reader
        card.readerConnected = true
        card.pin1 = CredentialState(
          value: activationPIN,
          attemptsRemaining: RetryCount.pristineAllowance,
          isFactoryValue: true)
        card.pin2 = CredentialState(
          value: activationPIN,
          attemptsRemaining: RetryCount.pristineAllowance,
          isFactoryValue: true)

      case .activatedReader:
        card.transport = .reader
        card.readerConnected = true

      case .pin1RecoveryReader:
        card.transport = .reader
        card.readerConnected = true
        card.pin1.attemptsRemaining = RetryCount.lowAttemptCeiling

      case .pin2RecoveryReader:
        card.transport = .reader
        card.readerConnected = true
        card.pin2.attemptsRemaining = RetryCount.lowAttemptCeiling

      case .pukRecoveryRefusedReader:
        card.transport = .reader
        card.readerConnected = true
        card.pin1.attemptsRemaining = 0
        card.puk.attemptsRemaining = RetryCount.lowAttemptCeiling

      case .absent:
        card.cardPresent = false
      }
      return Snapshot(card: card, device: device)
    }
  }

  /// A card operation that a queued fault can intercept.
  public enum Operation: String, CaseIterable, Sendable {
    case any = "any"
    case connect = "connect"
    case probeCredentials = "probeCredentials"
    case changePIN1 = "changePIN1"
    case changePIN2 = "changePIN2"
    case resetPIN1 = "resetPIN1"
    case resetPIN2 = "resetPIN2"
    case activatePIN1 = "activatePIN1"
    case activatePIN2 = "activatePIN2"
    case register = "register"
    case publishToken = "publishToken"
    case authenticateSignature = "authenticateSignature"
    case qualifiedSignature = "qualifiedSignature"
  }

  /// The point within an operation at which a fault fires.
  ///
  /// A fault before the command prevents the card from acting; a fault
  /// after card execution loses only the response, leaving the card's
  /// state change in place.
  public enum FaultPhase: String, CaseIterable, Sendable {
    case beforeCommand = "beforeCommand"
    case afterCardExecution = "afterCardExecution"
  }

  /// The failure surfaced to the caller when a fault fires.
  public enum FaultEffect: String, CaseIterable, Sendable {
    case connectionLost = "connectionLost"
    case readerDisconnected = "readerDisconnected"
    case cardRemoved = "cardRemoved"
    case timeout = "timeout"
    case malformedResponse = "malformedResponse"
    case tokenNotPublished = "tokenNotPublished"
  }

  /// A deterministic transport failure queued against one operation.
  public struct Fault: Equatable, Sendable {
    /// The operation this fault intercepts.
    public var operation: Operation
    /// The phase at which the fault fires.
    public var phase: FaultPhase
    /// The failure surfaced when the fault fires.
    public var effect: FaultEffect
    /// How many more times the fault fires before it expires.
    public var remainingOccurrences: Int

    /// Creates a fault that fires at least once.
    public init(
      operation: Operation,
      phase: FaultPhase,
      effect: FaultEffect,
      remainingOccurrences: Int = 1
    ) {
      self.operation = operation
      self.phase = phase
      self.effect = effect
      self.remainingOccurrences = max(1, remainingOccurrences)
    }
  }

  /// A named fault queue for common failure demonstrations.
  public enum FaultPreset: String, CaseIterable, Sendable {
    case noFault = "noFault"
    case nfcDisconnectBeforeConnection = "nfcDisconnectBeforeConnection"
    case readerFailsCounterQuery = "readerFailsCounterQuery"
    case cardRemovedDuringPINChange = "cardRemovedDuringPINChange"
    case responseLostAfterPIN1Activation = "responseLostAfterPIN1Activation"
    case responseLostAfterPIN2Activation = "responseLostAfterPIN2Activation"
    case certificateReadFailure = "certificateReadFailure"
    case tokenPublicationFailure = "tokenPublicationFailure"
    case cardRemovedDuringSignature = "cardRemovedDuringSignature"
    case responseLostAfterSignature = "responseLostAfterSignature"

    /// Whether the fault can only occur on the near-field transport.
    public var usesNearField: Bool {
      self == .nfcDisconnectBeforeConnection
    }

    /// The fault queue this preset enqueues.
    public var faults: [Fault] {
      switch self {
      case .noFault:
        []

      case .nfcDisconnectBeforeConnection:
        [Fault(operation: .connect, phase: .beforeCommand, effect: .connectionLost)]

      case .readerFailsCounterQuery:
        [
          Fault(
            operation: .probeCredentials,
            phase: .beforeCommand,
            effect: .readerDisconnected)
        ]

      case .cardRemovedDuringPINChange:
        [
          Fault(
            operation: .changePIN1,
            phase: .beforeCommand,
            effect: .cardRemoved)
        ]

      case .responseLostAfterPIN1Activation:
        [
          Fault(
            operation: .activatePIN1,
            phase: .afterCardExecution,
            effect: .connectionLost)
        ]

      case .responseLostAfterPIN2Activation:
        [
          Fault(
            operation: .activatePIN2,
            phase: .afterCardExecution,
            effect: .connectionLost)
        ]

      case .certificateReadFailure:
        [
          Fault(
            operation: .register,
            phase: .beforeCommand,
            effect: .malformedResponse)
        ]

      case .tokenPublicationFailure:
        [
          Fault(
            operation: .register,
            phase: .afterCardExecution,
            effect: .tokenNotPublished)
        ]

      case .cardRemovedDuringSignature:
        [
          Fault(
            operation: .qualifiedSignature,
            phase: .beforeCommand,
            effect: .cardRemoved)
        ]

      case .responseLostAfterSignature:
        [
          Fault(
            operation: .qualifiedSignature,
            phase: .afterCardExecution,
            effect: .connectionLost)
        ]
      }
    }
  }
}
