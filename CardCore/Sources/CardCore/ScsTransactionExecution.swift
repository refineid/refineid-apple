// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The `execute` step's validation, signing, and response rules
/// (DVV SCS specification v1.3 §2.7.3), split from the transaction
/// manager so each half stays readable.
internal enum ScsTransactionExecution {
  /// Runs one decrypted `execute` payload to its encrypted answer.
  internal static func respond(
    payload: ScsExecuteDocument,
    state: ScsAgreedTransaction,
    backend: any ScsSigningBackend
  ) -> Result<String, ScsTransactionError> {
    if let refused = refusal(
      payload: payload,
      purpose: state.purpose,
      serverKey: state.serverKey,
      origin: state.origin
    ) {
      return .failure(refused)
    }
    guard
      let hash = ScsKeyAlgorithm.hash(named: payload.hashAlgorithm),
      let content = Data(base64Encoded: payload.content)
    else {
      return .failure(.badRequest("execute content is not base64"))
    }
    let produced: Data
    switch signature(
      content: content,
      signatureType: payload.signatureType,
      hash: hash,
      state: state,
      backend: backend
    ) {
    case .success(let bytes):
      produced = bytes

    case .failure(let error):
      return .failure(error)
    }
    let response = ScsExecuteResponseDocument(
      version: ScsValues.version,
      signatureAlgorithm: payload.hashAlgorithm + "with" + payload.signatureAlgorithm,
      signatureType: payload.signatureType,
      signature: produced.base64EncodedString(),
      chain: backend.certificateChain(for: state.purpose).map { certificate in
        certificate.base64EncodedString()
      },
      status: "ok",
      reasonCode: ScsValues.reasonOk,
      reasonText: "Signature generated"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let plaintext = try? encoder.encode(response) else {
      return .failure(.internalError("serialize execute response"))
    }
    return ScsJsonWebEncryption.encrypt(plaintext: plaintext, key: state.key)
  }

  /// Why the decrypted `execute` payload is refused, or nil.
  internal static func refusal(
    payload: ScsExecuteDocument,
    purpose: ScsSignPurpose,
    serverKey: String,
    origin: String
  ) -> ScsTransactionError? {
    guard payload.version == ScsValues.version else {
      return .badRequest("unsupported transaction version \(payload.version)")
    }
    guard ScsKeyAlgorithm.hash(named: payload.hashAlgorithm) != nil else {
      return .notImplemented("unsupported hash algorithm \(payload.hashAlgorithm)")
    }
    guard
      payload.signatureAlgorithm == "RSA" || payload.signatureAlgorithm == "ECDSA"
    else {
      return .notImplemented(
        "unsupported signature algorithm \(payload.signatureAlgorithm)")
    }
    guard
      payload.signatureType == "signature" || payload.signatureType == "cms-pades"
    else {
      return .notImplemented("unsupported signature type \(payload.signatureType)")
    }
    switch payload.contentType {
    case "data":
      break

    case "digest" where purpose == .authentication:
      return .badRequest("authentication requests cannot use digest content")

    case "digest" where payload.signatureType == "cms-pades":
      break

    case "digest":
      return .notImplemented("pre-hashed raw card signing is not implemented")

    case let other:
      return .badRequest("unsupported content type \(other)")
    }
    guard purpose == .authentication else { return nil }
    return challengeRefusal(content: payload.content, serverKey: serverKey, origin: origin)
  }

  /// Produces the signature bytes for one validated `execute`.
  internal static func signature(
    content: Data,
    signatureType: String,
    hash: SigningHash,
    state: ScsAgreedTransaction,
    backend: any ScsSigningBackend
  ) -> Result<Data, ScsTransactionError> {
    let purpose = state.purpose
    guard signatureType == "cms-pades" else {
      do {
        return .success(
          try backend.sign(
            ScsSignRequest(
              purpose: purpose, hash: hash, data: content, origin: state.origin)))
      } catch {
        return .failure(.wrapping(error))
      }
    }
    let cms: ScsDetachedCms
    switch ScsDetachedCms.prepare(
      digest: content,
      certificates: backend.certificateChain(for: purpose),
      hashName: ScsKeyAlgorithm.scsName(hash: hash)
    ) {
    case .success(let prepared):
      cms = prepared

    case .failure(let error):
      return .failure(error)
    }
    do {
      let cardSignature = try backend.sign(
        ScsSignRequest(
          purpose: purpose, hash: hash, data: cms.signedAttributes, origin: state.origin))
      return .success(cms.signedData(signature: cardSignature))
    } catch {
      return .failure(.wrapping(error))
    }
  }

  /// The transaction form of the origin-bound challenge: the content
  /// must be `origin;nonce;serverKey`, binding the sign to both the
  /// caller and the key agreement (v1.3 §2.7.3).
  private static func challengeRefusal(
    content: String,
    serverKey: String,
    origin: String
  ) -> ScsTransactionError? {
    guard
      let raw = Data(base64Encoded: content),
      let challenge = String(data: raw, encoding: .utf8)
    else {
      return .badRequest("authentication challenge must be UTF-8")
    }
    let prefix = origin + ";"
    let suffix = ";" + serverKey
    guard challenge.hasPrefix(prefix), challenge.hasSuffix(suffix) else {
      return .forbidden(
        "transaction authentication challenge is not bound to Origin and serverKey")
    }
    let nonce = challenge.dropFirst(prefix.count).dropLast(suffix.count)
    guard nonce.count >= ScsValues.nonceMinimumLength else {
      return .badRequest("authentication challenge nonce is shorter than 64 octets")
    }
    return nil
  }
}
