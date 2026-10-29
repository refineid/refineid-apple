// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(MultipeerConnectivity) && canImport(RappEngine)
  import Foundation
  import RappEngine

  /// How the RAPP token extension hands an operation to the app on the same
  /// Mac, so the app carries it on the session it holds with the phone.
  ///
  /// A Mac holds one session to its phone, and the app holds it, on either
  /// transport. Every process of one Mac shares a single Bluetooth link and
  /// GATT client to the phone, which the phone sees as one central with one
  /// channel characteristic (RAPP v26.10.29 §5.2): a second RAPP connection
  /// from the extension would interleave its fragments with the app's, and
  /// on the stream it would be a second session beside the app's. So the
  /// extension asks the running app to carry its operation, and the app
  /// answers with the operation's outcome; the extension dials itself only
  /// when no app holds the port.
  ///
  /// The message is a property list whose every field is named, read back
  /// at one border; it carries exactly what an operation request carries on
  /// the wire, and never a PIN. Every case travels by its name, which both
  /// ends compile from the same source.
  public enum RappHeldSessionHandoff {
    // MARK: Nested Types

    /// An operation the extension asks the app to carry.
    public struct Request: Sendable, Equatable {
      /// The pairing the extension's identity was published for, when it
      /// knows it.
      public let pairID: Data?
      /// What the custodian is asked for.
      public let operation: RappRequesterOperation

      /// A request for `operation` over the pairing `pairID`.
      public init(pairID: Data?, operation: RappRequesterOperation) {
        self.pairID = pairID
        self.operation = operation
      }

      /// The request an encoded message names, or nil for any message
      /// that is not one.
      public init?(encoded: Data) {
        let fields = Coding.fields(encoded)
        let pair = fields[Key.pair] as? Data
        if let pair, pair.count != Coding.pairIdentifierByteCount { return nil }
        guard let named = Coding.operation(fields) else { return nil }
        self.init(pairID: pair, operation: named)
      }

      /// The message carrying this request.
      public func encoded() -> Data? {
        var fields = Coding.fields(of: operation)
        if let pairID { fields[Key.pair] = pairID }
        return Coding.encode(fields)
      }
    }

    /// What the app answers.
    public enum Answer: Sendable, Equatable {
      /// Why the operation produced no answer.
      case failed(RappRequesterClientError)
      /// The operation's answer.
      case response(RappRequesterResponse)

      /// The answer an encoded message names, or nil for any message that
      /// is not one.
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

      /// The message carrying this answer.
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

    /// The field names of a message.
    private enum Key {
      static let answer = "answer"
      static let pair = "pair"
      static let operation = "operation"
      static let context = "context"
      static let keyProfile = "keyProfile"
      static let algorithm = "algorithm"
      static let digest = "digest"
      static let response = "response"
      static let bytes = "bytes"
      static let error = "error"
      static let reason = "reason"
    }

    /// The values a message names kinds with.
    private enum Tag {
      static let response = "response"
      static let failed = "failed"
      static let terminal = "terminal"
      static let browserAuthentication = "browserAuthentication"
      static let documentSigning = "documentSigning"
    }

    /// The encoding both directions share.
    private enum Coding {
      /// RAPP pair identifiers are 16 bytes (RAPP v26.10.29 §4.3 item 2).
      static let pairIdentifierByteCount = 16

      /// The requester errors that carry nothing.
      static let plainErrors: [RappRequesterClientError] = [
        .noActivePair, .noSelectedPair, .peerNotFound, .protocolFailure, .timedOut, .transport,
        .unexpectedResult,
      ]

      /// The operations that carry nothing.
      static let plainOperations: [RappRequesterOperation] = [
        .readAuthenticationCertificate, .readSignatureCertificate,
      ]

      /// A case's name, without what it carries.
      static func name(_ value: some Any) -> String {
        String(String(describing: value).prefix { $0 != "(" })
      }

      /// The case of `cases` named `name`.
      static func named<Value>(_ name: String?, among cases: [Value]) -> Value? {
        guard let name else { return nil }
        return cases.first { self.name($0) == name }
      }

      static func encode(_ fields: [String: Any]) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: fields, format: .binary, options: 0)
      }

      /// The fields of a message; none for anything that is not one.
      static func fields(_ encoded: Data) -> [String: Any] {
        let decoded = try? PropertyListSerialization.propertyList(from: encoded, format: nil)
        return decoded as? [String: Any] ?? [:]
      }

      static func fields(of operation: RappRequesterOperation) -> [String: Any] {
        switch operation {
        case .readAuthenticationCertificate, .readSignatureCertificate:
          return [Key.operation: name(operation)]

        case .browserAuthentication(let context, let keyProfile, let algorithm, let digest):
          var fields = signing(keyProfile: keyProfile, algorithm: algorithm, digest: digest)
          fields[Key.operation] = Tag.browserAuthentication
          fields[Key.context] = context
          return fields

        case .documentSigning(let documentName, let keyProfile, let algorithm, let digest):
          var fields = signing(keyProfile: keyProfile, algorithm: algorithm, digest: digest)
          fields[Key.operation] = Tag.documentSigning
          fields[Key.context] = documentName
          return fields
        }
      }

      static func operation(_ fields: [String: Any]) -> RappRequesterOperation? {
        let kind = fields[Key.operation] as? String
        if let read = named(kind, among: plainOperations) { return read }
        guard let context = fields[Key.context] as? String,
          let keyProfile = named(
            fields[Key.keyProfile] as? String, among: RappOperationDriver.KeyProfile.allCases),
          let algorithm = named(
            fields[Key.algorithm] as? String,
            among: RappOperationDriver.SignatureAlgorithm.allCases),
          let digest = fields[Key.digest] as? Data
        else { return nil }
        switch kind {
        case Tag.browserAuthentication:
          return .browserAuthentication(
            displayContext: context, keyProfile: keyProfile, algorithm: algorithm, digest: digest)

        case Tag.documentSigning:
          return .documentSigning(
            documentName: context, keyProfile: keyProfile, algorithm: algorithm, digest: digest)

        default:
          return nil
        }
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

      private static func signing(
        keyProfile: RappOperationDriver.KeyProfile,
        algorithm: RappOperationDriver.SignatureAlgorithm,
        digest: Data
      ) -> [String: Any] {
        [Key.keyProfile: name(keyProfile), Key.algorithm: name(algorithm), Key.digest: digest]
      }
    }

    // MARK: Static Properties

    /// The port the app listens on.
    ///
    /// The sandbox lets members of an app group share a Mach port only under
    /// a name that begins with the group's identifier.
    public static let portName = "group.fi.refineid.RefineID.rapp-held-session"

    /// The identifier of the one message the port takes.
    public static let requestMessageID: Int32 = 1

    /// How long a request may take to reach the app, in seconds.
    public static let sendTimeoutSeconds: TimeInterval = 1

    /// How long the app waits for its session to the phone to come up
    /// before it gives a handed-over operation up, in seconds: one
    /// Bluetooth scan.
    public static let establishWaitSeconds: TimeInterval = 30

    /// How long the extension waits for the app's answer, in seconds: the
    /// session's wait, then the operation's own synchronous wait.
    public static var answerWaitSeconds: TimeInterval {
      establishWaitSeconds + RappRequesterPolicy.offeredIdentity.synchronousWaitTimeout
    }

    // MARK: Static Functions

    #if os(macOS)
      /// Asks the app to carry `request`, waiting at most
      /// ``answerWaitSeconds`` for its answer; nil only when no app holds
      /// the port, so the extension may dial the phone itself.
      ///
      /// An app that holds the port carries the operation on its session:
      /// one busy with an earlier request, or one that did not answer in
      /// time, may still be running the operation on the phone. That is a
      /// failure, never a reason to open a second session or start the
      /// operation a second time.
      public static func ask(_ request: Request) -> Answer? {
        guard let payload = request.encoded() else { return .failed(.protocolFailure) }
        guard let remote = CFMessagePortCreateRemote(nil, portName as CFString) else { return nil }
        defer { CFMessagePortInvalidate(remote) }
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(
          remote, requestMessageID, payload as CFData, sendTimeoutSeconds, answerWaitSeconds,
          CFRunLoopMode.defaultMode.rawValue, &reply)
        switch status {
        case kCFMessagePortSuccess:
          guard let reply else { return .failed(.protocolFailure) }
          return Answer(encoded: reply.takeRetainedValue() as Data) ?? .failed(.protocolFailure)

        case kCFMessagePortSendTimeout, kCFMessagePortReceiveTimeout:
          return .failed(.timedOut)

        case kCFMessagePortIsInvalid, kCFMessagePortBecameInvalidError:
          // The app quit: no session of its own carries the operation.
          return nil

        default:
          return .failed(.transport)
        }
      }
    #endif
  }
#endif
