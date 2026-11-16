// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Authenticated local handoff between `RappTokenExtension` and `RefineID.app` on the same Mac.
  ///
  /// Every process on one Mac shares a single Bluetooth link and GATT client to
  /// the paired phone (RAPP v26.11.8 §5.2). When `RefineID.app` is running, the
  /// token extension hands CryptoTokenKit client-authentication signing requests
  /// over a peer-verified local stream socket in the shared app-group container;
  /// the extension dials the phone directly only when no verified app instance
  /// holds the listener.
  ///
  /// External handoff requests require an explicit 16-byte `pairID`, accept only
  /// client-authentication signing parameters, and always materialize the fixed
  /// `"macOS CryptoTokenKit"` display context on the server. PINs never appear.
  public enum RappHeldSessionHandoff {
    /// A CryptoTokenKit client-authentication signing request handed to the running app.
    public struct Request: Sendable, Equatable {
      /// The 16-byte pairing identifier the extension's persistent token belongs to.
      public let pairID: Data

      /// The key profile selected for the signing operation.
      public let keyProfile: RappOperationDriver.KeyProfile

      /// The signature algorithm selected for the signing operation.
      public let algorithm: RappOperationDriver.SignatureAlgorithm

      /// The client-authentication digest to sign.
      public let digest: Data

      /// The server-enforced RAPP requester operation materialized from this request.
      public var operation: RappRequesterOperation {
        .browserAuthentication(
          displayContext: RappHeldSessionHandoff.cryptoTokenKitDisplayContext,
          keyProfile: keyProfile,
          algorithm: algorithm,
          digest: digest
        )
      }

      /// Creates a validated handoff request for a 16-byte `pairID` and bounded non-empty `digest`.
      public init?(
        pairID: Data,
        keyProfile: RappOperationDriver.KeyProfile,
        algorithm: RappOperationDriver.SignatureAlgorithm,
        digest: Data
      ) {
        guard
          pairID.count == RappHeldSessionHandoff.pairIdentifierByteCount,
          !digest.isEmpty,
          digest.count <= RappHeldSessionHandoff.maximumDigestByteCount
        else {
          return nil
        }
        self.pairID = pairID
        self.keyProfile = keyProfile
        self.algorithm = algorithm
        self.digest = digest
      }

      /// Decodes a request message, rejecting missing `pairID`, disallowed operations, or extra keys.
      public init?(encoded: Data) {
        let fields = Coding.fields(encoded)
        guard
          Set(fields.keys) == Coding.requestKeys,
          fields[Key.operation] as? String == Tag.browserAuthentication,
          let decodedPair = fields[Key.pair] as? Data,
          let decodedProfile = Coding.named(
            fields[Key.keyProfile] as? String,
            among: RappOperationDriver.KeyProfile.allCases
          ),
          let decodedAlgorithm = Coding.named(
            fields[Key.algorithm] as? String,
            among: RappOperationDriver.SignatureAlgorithm.allCases
          ),
          let decodedDigest = fields[Key.digest] as? Data
        else {
          return nil
        }
        self.init(
          pairID: decodedPair,
          keyProfile: decodedProfile,
          algorithm: decodedAlgorithm,
          digest: decodedDigest
        )
      }

      /// Encodes this request as a binary property list.
      public func encoded() -> Data? {
        Coding.encode([
          Key.operation: Tag.browserAuthentication,
          Key.pair: pairID,
          Key.keyProfile: Coding.name(keyProfile),
          Key.algorithm: Coding.name(algorithm),
          Key.digest: digest,
        ])
      }
    }

    /// The outcome the running app returns for a handed-over request.
    public enum Answer: Sendable, Equatable {
      /// Why the operation produced no signature.
      case failed(RappRequesterClientError)

      /// The operation's response payload.
      case response(RappRequesterResponse)

      /// Decodes an answer message, or returns nil for malformed payloads.
      public init?(encoded: Data) {
        let fields = Coding.fields(encoded)
        switch fields[Key.answer] as? String {
        case Tag.failed:
          guard let error = Coding.error(fields) else { return nil }
          self = .failed(error)

        case Tag.response:
          guard let response = Coding.response(fields) else { return nil }
          self = .response(response)

        default:
          return nil
        }
      }

      /// Encodes this answer as a binary property list.
      public func encoded() -> Data? {
        switch self {
        case .failed(let error):
          var fields = Coding.fields(of: error)
          fields[Key.answer] = Tag.failed
          return Coding.encode(fields)

        case .response(let response):
          var fields = Coding.fields(of: response)
          fields[Key.answer] = Tag.response
          return Coding.encode(fields)
        }
      }
    }

    /// Property-list dictionary keys used on the local handoff wire.
    private enum Key {
      static let answer = "answer"
      static let pair = "pair"
      static let operation = "operation"
      static let keyProfile = "keyProfile"
      static let algorithm = "algorithm"
      static let digest = "digest"
      static let response = "response"
      static let bytes = "bytes"
      static let error = "error"
      static let reason = "reason"
    }

    /// Discriminator tags used in encoded handoff messages.
    private enum Tag {
      static let response = "response"
      static let failed = "failed"
      static let terminal = "terminal"
      static let browserAuthentication = "browserAuthentication"
    }

    /// Shared property-list serialization helpers for requests and answers.
    private enum Coding {
      static let requestKeys: Set<String> = [
        Key.operation, Key.pair, Key.keyProfile, Key.algorithm, Key.digest,
      ]

      static let plainErrors: [RappRequesterClientError] = [
        .noActivePair, .noSelectedPair, .peerNotFound, .protocolFailure, .timedOut, .transport,
        .unexpectedResult,
      ]

      static func name(_ value: some Any) -> String {
        String(String(describing: value).prefix { $0 != "(" })
      }

      static func named<Value>(_ name: String?, among cases: [Value]) -> Value? {
        guard let name else { return nil }
        return cases.first { self.name($0) == name }
      }

      static func encode(_ fields: [String: Any]) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: fields, format: .binary, options: 0)
      }

      static func fields(_ encoded: Data) -> [String: Any] {
        guard encoded.count <= RappHeldSessionHandoff.maximumMessageByteCount else { return [:] }
        let decoded = try? PropertyListSerialization.propertyList(from: encoded, format: nil)
        return decoded as? [String: Any] ?? [:]
      }

      static func fields(of response: RappRequesterResponse) -> [String: Any] {
        switch response {
        case .authenticationCertificate(let bytes), .signature(let bytes),
          .signatureCertificate(let bytes):
          [Key.response: name(response), Key.bytes: bytes]
        }
      }

      static func response(_ fields: [String: Any]) -> RappRequesterResponse? {
        guard let bytes = fields[Key.bytes] as? Data, !bytes.isEmpty else { return nil }
        let candidates: [RappRequesterResponse] = [
          .authenticationCertificate(bytes), .signature(bytes), .signatureCertificate(bytes),
        ]
        return named(fields[Key.response] as? String, among: candidates)
      }

      static func fields(of error: RappRequesterClientError) -> [String: Any] {
        guard case .terminal(let reason) = error else { return [Key.error: name(error)] }
        return [Key.error: Tag.terminal, Key.reason: name(reason)]
      }

      static func error(_ fields: [String: Any]) -> RappRequesterClientError? {
        let kind = fields[Key.error] as? String
        guard kind == Tag.terminal else { return named(kind, among: plainErrors) }
        return named(fields[Key.reason] as? String, among: RappTerminalReason.allCases)
          .map(RappRequesterClientError.terminal)
      }
    }

    /// RAPP pair identifiers are 16 bytes (RAPP v26.11.8 §4.3 item 2).
    public static let pairIdentifierByteCount = 16

    /// Upper bound on a raw digest payload handed over by CryptoTokenKit.
    public static let maximumDigestByteCount = 512

    /// Upper bound on any framed handoff message read from the local socket.
    public static let maximumMessageByteCount = 65_536

    /// Fixed display context enforced on the server for CryptoTokenKit handoffs.
    public static let cryptoTokenKitDisplayContext = "macOS CryptoTokenKit"

    /// Shared macOS app-group identifier hosting the handoff socket directory.
    public static let appGroupIdentifier = "group.fi.refineid.RefineID"

    /// Code-signing identifier expected of the macOS `RefineID.app` listener.
    public static let appSigningIdentifier = "fi.refineid.ReFineID"

    /// Code-signing identifier expected of the macOS `RappTokenExtension` caller.
    public static let tokenExtensionSigningIdentifier = "fi.refineid.ReFineID.rapp-token"

    /// Maximum seconds allowed when sending a request frame to the local listener.
    public static let sendTimeoutSeconds: TimeInterval = 1

    /// Seconds the app waits for its phone session to come up before failing a handoff.
    public static let establishWaitSeconds: TimeInterval = 30

    /// Total seconds the extension waits for the app's answer before timing out.
    public static var answerWaitSeconds: TimeInterval {
      establishWaitSeconds + RappRequesterPolicy.offeredIdentity.synchronousWaitTimeout
    }
  }
#endif
