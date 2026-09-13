// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// The Sendable values the driver hands to its caller, and the translations
  /// between them and the engine's own records.
  ///
  /// They live beside the actor rather than inside it so the actor reads as
  /// the operations it performs.
  extension RappOperationDriver {
    /// Local misuse of the driver or a bridge action missing a required field.
    public enum LocalError: Error, Sendable {
      case wrongPhase
      case missingOperation
      case missingOperationIdentifier
      case missingFrame
    }

    /// Caller-injected liveness polling policy with no hidden timing constants.
    public struct Liveness: Sendable, Equatable {
      /// Interval between liveness polls before any backoff.
      public let baseIntervalMilliseconds: UInt64
      /// Time allowed for the peer to answer one liveness challenge.
      public let responseTimeoutMilliseconds: UInt64
      /// Upper bound the polling interval may back off to.
      public let maximumIntervalMilliseconds: UInt64
      /// Largest random offset applied to a scheduled poll.
      public let maximumJitterMilliseconds: UInt64
      /// Consecutive unanswered challenges tolerated before closing.
      public let maximumMisses: UInt8

      internal var binding: RappLivenessConfiguration {
        RappLivenessConfiguration(
          baseIntervalMs: baseIntervalMilliseconds,
          responseTimeoutMs: responseTimeoutMilliseconds,
          maximumIntervalMs: maximumIntervalMilliseconds,
          maximumJitterMs: maximumJitterMilliseconds,
          maximumMisses: maximumMisses
        )
      }

      /// Creates a policy from explicit caller-chosen bounds.
      public init(
        baseIntervalMilliseconds: UInt64,
        responseTimeoutMilliseconds: UInt64,
        maximumIntervalMilliseconds: UInt64,
        maximumJitterMilliseconds: UInt64,
        maximumMisses: UInt8
      ) {
        self.baseIntervalMilliseconds = baseIntervalMilliseconds
        self.responseTimeoutMilliseconds = responseTimeoutMilliseconds
        self.maximumIntervalMilliseconds = maximumIntervalMilliseconds
        self.maximumJitterMilliseconds = maximumJitterMilliseconds
        self.maximumMisses = maximumMisses
      }
    }

    /// Card signing key profile named by an operation request.
    public enum KeyProfile: Sendable, Equatable {
      case ecdsaP256
      case ecdsaP384
      case rsa2048
      case rsa3072

      internal var binding: RappCardKeyProfile {
        switch self {
        case .ecdsaP256:
          .ecdsaP256

        case .ecdsaP384:
          .ecdsaP384

        case .rsa2048:
          .rsa2048

        case .rsa3072:
          .rsa3072
        }
      }

      internal init(_ value: RappCardKeyProfile) {
        switch value {
        case .ecdsaP256:
          self = .ecdsaP256

        case .ecdsaP384:
          self = .ecdsaP384

        case .rsa2048:
          self = .rsa2048

        case .rsa3072:
          self = .rsa3072
        }
      }
    }

    /// Signature algorithm named by an operation request.
    public enum SignatureAlgorithm: Sendable, Equatable {
      case ecdsaSHA224
      case ecdsaSHA256
      case ecdsaSHA384
      case ecdsaSHA512
      case rsaPkcs1SHA256
      case rsaPkcs1SHA384
      case rsaPkcs1SHA512
      case rsaPssSHA256

      internal var binding: RappSignatureAlgorithm {
        switch self {
        case .ecdsaSHA224:
          .ecdsaSha224

        case .ecdsaSHA256:
          .ecdsaSha256

        case .ecdsaSHA384:
          .ecdsaSha384

        case .ecdsaSHA512:
          .ecdsaSha512

        case .rsaPkcs1SHA256:
          .rsaPkcs1Sha256

        case .rsaPkcs1SHA384:
          .rsaPkcs1Sha384

        case .rsaPkcs1SHA512:
          .rsaPkcs1Sha512

        case .rsaPssSHA256:
          .rsaPssSha256
        }
      }

      internal init(_ value: RappSignatureAlgorithm) {
        switch value {
        case .ecdsaSha224:
          self = .ecdsaSHA224

        case .ecdsaSha256:
          self = .ecdsaSHA256

        case .ecdsaSha384:
          self = .ecdsaSHA384

        case .ecdsaSha512:
          self = .ecdsaSHA512

        case .rsaPkcs1Sha256:
          self = .rsaPkcs1SHA256

        case .rsaPkcs1Sha384:
          self = .rsaPkcs1SHA384

        case .rsaPkcs1Sha512:
          self = .rsaPkcs1SHA512

        case .rsaPssSha256:
          self = .rsaPssSHA256
        }
      }
    }

    /// Kind of operation the requester asks the proxy to perform.
    public enum OperationKind: Sendable, Equatable {
      case inspectCard
      case readIdentity
      case readAuthenticationCertificate
      case readSignatureCertificate
      case readRootCertificate
      case readIntermediateCertificate
      case browserAuthenticate
      case signDocument

      internal init(_ value: RappOperationKind) {
        switch value {
        case .inspectCard:
          self = .inspectCard

        case .readIdentity:
          self = .readIdentity

        case .readAuthenticationCertificate:
          self = .readAuthenticationCertificate

        case .readSignatureCertificate:
          self = .readSignatureCertificate

        case .readRootCertificate:
          self = .readRootCertificate

        case .readIntermediateCertificate:
          self = .readIntermediateCertificate

        case .browserAuthenticate:
          self = .browserAuthenticate

        case .signDocument:
          self = .signDocument
        }
      }
    }

    /// One requested operation, described without any local credentials.
    public struct Operation: Sendable, Equatable {
      /// Requested operation kind.
      public let kind: OperationKind
      /// User-visible request context such as an origin or a document name.
      public let displayContext: String?
      /// Card key profile for signing operations; nil otherwise.
      public let keyProfile: KeyProfile?
      /// Signature algorithm for signing operations; nil otherwise.
      public let algorithm: SignatureAlgorithm?
      /// Digest to be signed; empty for non-signing operations.
      public let digest: Data

      internal init(_ value: RappOperationDescriptor) {
        kind = OperationKind(value.kind)
        displayContext = value.displayContext
        keyProfile = value.keyProfile.map(KeyProfile.init)
        algorithm = value.algorithm.map(SignatureAlgorithm.init)
        digest = value.digest
      }
    }

    /// Kind of a successfully completed operation result.
    public enum ResultKind: Sendable, Equatable {
      case inspection
      case identity
      case certificate
      case signature

      internal init(_ value: RappResultKind) {
        switch value {
        case .inspection:
          self = .inspection

        case .identity:
          self = .identity

        case .certificate:
          self = .certificate

        case .signature:
          self = .signature
        }
      }
    }

    /// Card factory and retry state produced by an inspection.
    public struct Inspection: Sendable, Equatable {
      /// Whether PIN 1 still carries its factory value.
      public let pin1Factory: Bool
      /// Whether PIN 2 still carries its factory value.
      public let pin2Factory: Bool
      /// Remaining PIN 1 attempts when reported.
      public let pin1Attempts: UInt8?
      /// Remaining PIN 2 attempts when reported.
      public let pin2Attempts: UInt8?
      /// Remaining PUK attempts when reported.
      public let pukAttempts: UInt8?

      /// Creates an inspection result describing card state.
      public init(
        pin1Factory: Bool,
        pin2Factory: Bool,
        pin1Attempts: UInt8? = nil,
        pin2Attempts: UInt8? = nil,
        pukAttempts: UInt8? = nil
      ) {
        self.pin1Factory = pin1Factory
        self.pin2Factory = pin2Factory
        self.pin1Attempts = pin1Attempts
        self.pin2Attempts = pin2Attempts
        self.pukAttempts = pukAttempts
      }
    }

    /// Successful operation result with only the fields its kind populates.
    public struct Result: Sendable, Equatable {
      /// Result kind that selects which optional fields are populated.
      public let kind: ResultKind
      /// Whether PIN 1 still carries its factory value; inspection only.
      public let pin1FactoryReported: Bool
      /// Whether PIN 1 still carries its factory value when reported.
      public let pin1Factory: Bool
      /// Whether PIN 2 still carries its factory value; inspection only.
      public let pin2FactoryReported: Bool
      /// Whether PIN 2 still carries its factory value when reported.
      public let pin2Factory: Bool
      /// Remaining PIN 1 attempts when the card reported them.
      public let pin1Attempts: UInt8?
      /// Remaining PIN 2 attempts when the card reported them.
      public let pin2Attempts: UInt8?
      /// Remaining PUK attempts when the card reported them.
      public let pukAttempts: UInt8?
      /// Cardholder display name carried by identity results.
      public let displayName: String?
      /// Cardholder person identifier carried by identity results.
      public let personID: String?
      /// Certificate DER or signature bytes; empty for other result kinds.
      public let bytes: Data

      internal init(_ value: RappOperationResult) {
        kind = ResultKind(value.kind)
        pin1FactoryReported = value.pin1Factory != nil
        pin1Factory = value.pin1Factory ?? false
        pin2FactoryReported = value.pin2Factory != nil
        pin2Factory = value.pin2Factory ?? false
        pin1Attempts = value.pin1Attempts
        pin2Attempts = value.pin2Attempts
        pukAttempts = value.pukAttempts
        displayName = value.displayName
        personID = value.personId
        bytes = value.bytes
      }
    }

    /// Reason an operation ended without delivering a result.
    public enum TerminalReason: Sendable, Equatable {
      case userDenied
      case requestExpired
      case cancelled
      case requestInvalidOrUnsupported
      case retryPolicyRefused
      case credentialRejected
      case cardRemovedBeforeTransmit
      case cardCompletionAmbiguous

      internal init(_ value: RappTerminalReason) {
        switch value {
        case .userDenied:
          self = .userDenied

        case .requestExpired:
          self = .requestExpired

        case .cancelled:
          self = .cancelled

        case .requestInvalidOrUnsupported:
          self = .requestInvalidOrUnsupported

        case .retryPolicyRefused:
          self = .retryPolicyRefused

        case .credentialRejected:
          self = .credentialRejected

        case .cardRemovedBeforeTransmit:
          self = .cardRemovedBeforeTransmit

        case .cardCompletionAmbiguous:
          self = .cardCompletionAmbiguous
        }
      }
    }

    /// Reason the operation session closed permanently.
    public enum CloseReason: Sendable, Equatable {
      case localRequest
      case transportClosed
      case protocolFailure
      case pairRevoked
      case terminalFrameReleased
    }

    /// A token that the transport must return after it has released a frame.
    public enum FrameRelease: Sendable, Equatable {
      case noRelease
      case resultAcknowledgment(operationID: Data)
      case closeSession
    }

    /// Effect the caller must apply on behalf of the driver, which performs
    /// no card or transport I/O itself.
    public enum Command: Sendable, Equatable {
      case send(frame: Data, release: FrameRelease)
      case inspectPrerequisites(operationID: Data, operation: Operation)
      case awaitUserApproval(operationID: Data, operation: Operation)
      case executeSafeRead(operationID: Data, operation: Operation)
      case executeCardCommand(operationID: Data, operation: Operation)
      case completed(operationID: Data, result: Result)
      case terminal(operationID: Data?, state: String?, reason: TerminalReason?)
      case advisoryCancellation(operationID: Data?)
      case operationFinished(operationID: Data?)
      case peerBusy(operationID: Data?)
      case peerUnknownOperation(operationID: Data?)
      case progress(operationID: Data, event: ProgressEvent)
      case scheduleLiveness(atMonotonicMilliseconds: UInt64)
      case closed(CloseReason)
    }
  }

#endif
