// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Typed native command received from the Web eID Safari Web Extension.
public enum WebEidCommand: Codable, Equatable, Sendable {
  case authenticate(origin: WebEidOrigin, challengeNonce: String, lang: String?)
  case getSigningCertificate(origin: WebEidOrigin, lang: String?)
  case sign(SignRequest)
  case status

  /// Validated inputs for one Web eID `sign` command.
  public struct SignRequest: Codable, Equatable, Sendable {
    /// Relying-party HTTPS origin.
    public let origin: WebEidOrigin

    /// DER-encoded qualified signing certificate selected by the caller.
    public let certificateDER: Data

    /// Pre-computed document digest bytes.
    public let hash: Data

    /// Digest algorithm matching `hash`.
    public let hashFunction: WebEidHashFunction

    /// Optional UI language hint supplied by `web-eid.js`.
    public let lang: String?

    /// Creates a validated signing request.
    public init(
      origin: WebEidOrigin,
      certificateDER: Data,
      hash: Data,
      hashFunction: WebEidHashFunction,
      lang: String?
    ) {
      self.origin = origin
      self.certificateDER = certificateDER
      self.hash = hash
      self.hashFunction = hashFunction
      self.lang = lang
    }
  }

  /// Parses and validates a raw dictionary delivered through `SFExtensionMessageKey`.
  public static func parse(dictionary: [String: Any]) throws -> Self {
    guard let name = dictionary["command"] as? String else {
      throw WebEidError(
        code: .nativeInvalidArgument,
        message: "Missing command name"
      )
    }
    let arguments = dictionary["arguments"] as? [String: Any] ?? [:]
    switch name {
    case "status":
      return .status

    case "authenticate":
      return try parseAuthenticate(arguments)

    case "get-signing-certificate":
      return try parseGetSigningCertificate(arguments)

    case "sign":
      return try parseSign(arguments)

    default:
      throw WebEidError(
        code: .nativeInvalidArgument,
        message: "Unsupported Web eID command"
      )
    }
  }

  private static func parseAuthenticate(_ arguments: [String: Any]) throws -> Self {
    let origin = try requiredOrigin(from: arguments)
    guard let nonce = arguments["challengeNonce"] as? String else {
      throw WebEidError(
        code: .nativeInvalidArgument,
        message: "Missing challengeNonce argument"
      )
    }
    let validLength =
      WebEidValues.minimumChallengeNonceLength...WebEidValues.maximumChallengeNonceLength
    guard
      validLength.contains(nonce.count),
      nonce.unicodeScalars.allSatisfy(\.isASCII)
    else {
      throw WebEidError(
        code: .nativeInvalidArgument,
        message: "Challenge nonce length or encoding is invalid"
      )
    }
    return .authenticate(
      origin: origin,
      challengeNonce: nonce,
      lang: optionalLanguage(from: arguments)
    )
  }

  private static func parseGetSigningCertificate(_ arguments: [String: Any]) throws -> Self {
    let origin = try requiredOrigin(from: arguments)
    return .getSigningCertificate(
      origin: origin,
      lang: optionalLanguage(from: arguments)
    )
  }

  private static func parseSign(_ arguments: [String: Any]) throws -> Self {
    let origin = try requiredOrigin(from: arguments)
    guard
      let certBase64 = arguments["certificate"] as? String,
      !certBase64.isEmpty,
      let certificateDER = Data(base64Encoded: certBase64),
      !certificateDER.isEmpty
    else {
      throw WebEidError(
        code: .nativeInvalidArgument,
        message: "Invalid or missing signing certificate"
      )
    }
    guard
      let hashName = arguments["hashFunction"] as? String,
      hashName.count <= WebEidValues.maximumHashFunctionNameLength,
      let hashFunction = WebEidHashFunction(rawValue: hashName)
    else {
      throw WebEidError(
        code: .nativeInvalidArgument,
        message: "Unsupported hashFunction argument"
      )
    }
    guard
      let hashBase64 = arguments["hash"] as? String,
      !hashBase64.isEmpty,
      let hash = Data(base64Encoded: hashBase64),
      hash.count == hashFunction.digestByteCount
    else {
      throw WebEidError(
        code: .nativeInvalidArgument,
        message: "Document hash does not match hashFunction length"
      )
    }
    return .sign(
      SignRequest(
        origin: origin,
        certificateDER: certificateDER,
        hash: hash,
        hashFunction: hashFunction,
        lang: optionalLanguage(from: arguments)
      )
    )
  }

  private static func requiredOrigin(from arguments: [String: Any]) throws -> WebEidOrigin {
    guard
      let rawOrigin = arguments["origin"] as? String,
      let origin = WebEidOrigin(rawOrigin)
    else {
      throw WebEidError(
        code: .nativeInvalidArgument,
        message: "Origin must be a valid HTTPS URL without path or query"
      )
    }
    return origin
  }

  private static func optionalLanguage(from arguments: [String: Any]) -> String? {
    guard let lang = arguments["lang"] as? String, !lang.isEmpty else { return nil }
    return lang
  }
}
