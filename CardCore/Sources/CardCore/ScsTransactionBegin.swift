// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// The stateless work of the `begin` step.
///
/// JWS verification, key agreement, and the card-signed response JWT
/// (DVV SCS specification v1.3 §2.7.2). The manager owns only the
/// pending slot; everything else happens here.
internal enum ScsTransactionBegin {
  /// One completed begin: the compact response JWT and the agreed
  /// state the manager should hold for `execute`.
  internal struct Outcome {
    /// The signed compact response JWT.
    internal let response: String

    /// The agreed transaction awaiting `execute`.
    internal let state: ScsAgreedTransaction
  }

  /// Runs the whole begin step over already-split JWS segments.
  internal static func perform(
    segments: [String],
    origin: String,
    at now: Date,
    backend: any ScsSigningBackend
  ) -> Result<Outcome, ScsTransactionError> {
    let header: ScsJoseHeaderDocument
    let payload: ScsBeginDocument
    switch ScsTransactionCodec.decodeSegment(
      segments[0], as: ScsJoseHeaderDocument.self, label: "JWS header")
    {
    case .success(let decoded):
      header = decoded

    case .failure(let error):
      return .failure(error)
    }
    switch ScsTransactionCodec.decodeSegment(
      segments[1], as: ScsBeginDocument.self, label: "JWS payload")
    {
    case .success(let decoded):
      payload = decoded

    case .failure(let error):
      return .failure(error)
    }
    guard payload.version == ScsValues.version else {
      return .failure(.badRequest("unsupported transaction version \(payload.version)"))
    }
    guard let certificate = Data(base64Encoded: payload.serverCert) else {
      return .failure(.badRequest("serverCert is not base64"))
    }
    guard let signature = Base64Url.decode(segments[ScsValues.jwsSignatureIndex]) else {
      return .failure(.badRequest("JWS signature is not base64url"))
    }
    let signingInput = Data((segments[0] + "." + segments[1]).utf8)
    if let refusal = ScsJsonWebSignature.refusal(
      algorithm: header.alg,
      certificateDer: certificate,
      signingInput: signingInput,
      signature: signature,
      at: now
    ) {
      return .failure(refusal)
    }
    return agreed(payload: payload, origin: origin, backend: backend)
  }

  /// The key-agreement half, after JWS verification.
  private static func agreed(
    payload: ScsBeginDocument,
    origin: String,
    backend: any ScsSigningBackend
  ) -> Result<Outcome, ScsTransactionError> {
    let purpose: ScsSignPurpose
    switch ScsTransactionCodec.purpose(of: payload.selector) {
    case .success(let selected):
      purpose = selected

    case .failure(let error):
      return .failure(error)
    }
    let chain = backend.certificateChain(for: purpose).map { certificate in
      certificate.base64EncodedString()
    }
    guard !chain.isEmpty else {
      return .failure(.internalError("signing backend returned no end-user certificate"))
    }
    if let refusal = ScsTransactionCodec.selectorRefusal(
      payload, keyAlgorithm: backend.keyAlgorithm(for: purpose))
    {
      return .failure(refusal)
    }
    guard
      let serverKeyDer = Data(base64Encoded: payload.serverKey),
      let serverPublic = try? P256.KeyAgreement.PublicKey(derRepresentation: serverKeyDer)
    else {
      return .failure(.badRequest("serverKey is not a P-256 SPKI"))
    }
    let ephemeral = P256.KeyAgreement.PrivateKey()
    guard let shared = try? ephemeral.sharedSecretFromKeyAgreement(with: serverPublic) else {
      return .failure(.internalError("transaction key agreement failed"))
    }
    let response = ScsBeginResponseDocument(
      version: ScsValues.version,
      transaction: ephemeral.publicKey.derRepresentation.base64EncodedString(),
      chain: chain,
      status: "ok",
      reasonCode: ScsValues.reasonOk,
      reasonText: "Transaction started"
    )
    let state = ScsAgreedTransaction(
      key: SymmetricKey(data: shared),
      origin: origin,
      purpose: purpose,
      serverKey: payload.serverKey
    )
    return signed(response: response, purpose: purpose, backend: backend, state: state)
  }

  /// Signs the response JWT with the card.
  ///
  /// The JWS algorithm follows the card key: RS256 over SHA-256 for
  /// an RSA key, ES384 over SHA-384 for the P-384 key - the digest
  /// each card's qualified key actually serves (RFC 7518 section
  /// 3.1; the raw `r || s` card signature is already the ES384 JWS
  /// form).
  private static func signed(
    response: ScsBeginResponseDocument,
    purpose: ScsSignPurpose,
    backend: any ScsSigningBackend,
    state: ScsAgreedTransaction
  ) -> Result<Outcome, ScsTransactionError> {
    let algorithm: String
    let hash: SigningHash
    switch backend.keyAlgorithm(for: purpose) {
    case .ecdsa:
      algorithm = "ES384"
      hash = .sha384

    case .rsa:
      algorithm = "RS256"
      hash = .sha256
    }
    let header = ScsResponseHeaderDocument(
      alg: algorithm,
      kid: ScsTransactionCodec.keyIdentifier(chain: response.chain),
      typ: "JWT"
    )
    let encodedHeader: String
    let encodedPayload: String
    switch ScsTransactionCodec.encodeSegment(header) {
    case .success(let encoded):
      encodedHeader = encoded

    case .failure(let error):
      return .failure(error)
    }
    switch ScsTransactionCodec.encodeSegment(response) {
    case .success(let encoded):
      encodedPayload = encoded

    case .failure(let error):
      return .failure(error)
    }
    let signingInput = encodedHeader + "." + encodedPayload
    do {
      let signature = try backend.sign(
        ScsSignRequest(
          purpose: purpose, hash: hash, data: Data(signingInput.utf8), origin: state.origin))
      return .success(
        Outcome(
          response: signingInput + "." + Base64Url.encode(signature),
          state: state
        )
      )
    } catch {
      return .failure(.wrapping(error))
    }
  }
}
