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
      case browserAuthenticate
      case signDocument
      case batchSignDocuments

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

        case .browserAuthenticate:
          self = .browserAuthenticate

        case .signDocument:
          self = .signDocument

        case .batchSignDocuments:
          self = .batchSignDocuments
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
      /// A batch's document names in signing order; empty otherwise.
      public let documentNames: [String]
      /// A batch's digests, paired with `documentNames`; empty otherwise.
      public let digests: [Data]

      internal init(_ value: RappOperationDescriptor) {
        kind = OperationKind(value.kind)
        displayContext = value.displayContext
        keyProfile = value.keyProfile.map(KeyProfile.init)
        algorithm = value.algorithm.map(SignatureAlgorithm.init)
        digest = value.digest
        documentNames = value.documentNames
        digests = value.digests
      }
    }

    /// Why the operation session closed permanently.
    public enum CloseReason: Sendable, Equatable {
      case localRequest
      case transportClosed
      /// An authenticated protocol violation, sent or received, or a frame
      /// that failed authentication; the pairing stays (§10.1).
      case protocolFailure
      /// The peer revoked the pairing; revoke it here too and withdraw its
      /// identity (§4.6 item 4).
      case pairRevoked
      /// This endpoint's own close notice was released.
      case terminalFrameReleased
      /// The custodian stopped serving (`service_withdrawn`); the requester
      /// drops the card at once and redials only when it advertises again.
      case serviceWithdrawn
      /// The peer closed the session with another registered reason.
      case peerClosed(RappCloseReason)
    }

    /// A token that the transport must return after it has released a frame.
    public enum FrameRelease: Sendable, Equatable {
      case noRelease
      /// The frame was this endpoint's close; the session ends with it.
      case closeSession(CloseReason)
    }

    /// Effect the caller must apply on behalf of the driver, which performs
    /// no card or transport I/O itself.
    public enum Command: Sendable, Equatable {
      case send(frame: Data, release: FrameRelease)
      case inspectPrerequisites(operationID: RappOperationIdentifier, operation: Operation)
      case awaitUserApproval(operationID: RappOperationIdentifier, operation: Operation)
      case executeSafeRead(operationID: RappOperationIdentifier, operation: Operation)
      case executeCardCommand(operationID: RappOperationIdentifier, operation: Operation)
      case completed(operationID: RappOperationIdentifier, result: RappOperationResult)
      case terminal(operationID: RappOperationIdentifier, reason: RappTerminalReason)
      case progress(operationID: RappOperationIdentifier, event: ProgressEvent)
      /// The custodian's word on which card it can serve now (§8.4).
      case cardStatus(RappCardStatus)
      /// The session's operation ended with the session (§8.1 item 3).
      case operationEnded(RappEndedOperation)
      case closed(CloseReason)
    }
  }

#endif
