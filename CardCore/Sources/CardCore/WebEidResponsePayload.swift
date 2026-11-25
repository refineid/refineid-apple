// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Typed native response payload returned from `RefineID.app` to the Safari Web Extension.
public enum WebEidResponsePayload: Codable, Equatable, Sendable {
  case authenticate(AuthenticationToken)
  case getSigningCertificate(
    certificate: String,
    supportedSignatureAlgorithms: [WebEidSignatureAlgorithm]
  )
  case sign(
    signature: String,
    signatureAlgorithm: WebEidSignatureAlgorithm
  )
  case status(version: String)

  /// Signed Web eID authentication token fields (`web-eid:1.0`).
  public struct AuthenticationToken: Codable, Equatable, Sendable {
    /// Standard Base64-encoded DER authentication certificate.
    public let unverifiedCertificate: String

    /// JWS algorithm identifier (`ES256`, `ES384`, or `RS256`).
    public let algorithm: String

    /// Standard Base64-encoded raw card signature bytes.
    public let signature: String

    /// Web eID token format identifier (`"web-eid:1.0"`).
    public let format: String

    /// Public release URL naming the RefineID version that created the token.
    public let appVersion: String

    /// Creates a signed Web eID authentication token payload.
    public init(
      unverifiedCertificate: String,
      algorithm: String,
      signature: String,
      format: String,
      appVersion: String
    ) {
      self.unverifiedCertificate = unverifiedCertificate
      self.algorithm = algorithm
      self.signature = signature
      self.format = format
      self.appVersion = appVersion
    }
  }

  /// Converts the payload to the plain dictionary returned through `SFExtensionMessageKey`.
  public func toDictionary() -> [String: Any] {
    switch self {
    case .authenticate(let token):
      return [
        "unverifiedCertificate": token.unverifiedCertificate,
        "algorithm": token.algorithm,
        "signature": token.signature,
        "format": token.format,
        "appVersion": token.appVersion,
      ]

    case .getSigningCertificate(let certificate, let supportedSignatureAlgorithms):
      return [
        "certificate": certificate,
        "supportedSignatureAlgorithms": supportedSignatureAlgorithms.map { $0.toDictionary() },
      ]

    case .sign(let signature, let signatureAlgorithm):
      return [
        "signature": signature,
        "signatureAlgorithm": signatureAlgorithm.toDictionary(),
      ]

    case .status(let version):
      return ["version": version]
    }
  }
}
