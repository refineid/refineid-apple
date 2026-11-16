// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// The stateless helpers under the SCS transaction flow: origin and
/// selector gates, JOSE segment coding, and the response key
/// identifier (DVV SCS specification v1.3 §2.7).
internal enum ScsTransactionCodec {
  /// The transaction Origin gate: present and a valid HTTPS web origin
  /// (v1.3 §2.1, §2.7).
  internal static func validatedOrigin(
    _ origin: String?
  ) -> Result<String, ScsTransactionError> {
    guard let origin else {
      return .failure(.forbidden("missing Origin header"))
    }
    if let refusal = ScsOriginPolicy.refusal(forPresentOrigin: origin) {
      return .failure(.forbidden(refusal))
    }
    return .success(origin)
  }

  /// The card key the selector names; mixing both usages is
  /// refused.
  internal static func purpose(
    of selector: ScsBeginSelectorDocument?
  ) -> Result<ScsSignPurpose, ScsTransactionError> {
    let usages = selector?.keyusages ?? []
    let qualified = usages.contains { usage in
      usage.caseInsensitiveCompare("nonRepudiation") == .orderedSame
    }
    let authentication = usages.contains { usage in
      usage.caseInsensitiveCompare("digitalSignature") == .orderedSame
    }
    if qualified, authentication {
      return .failure(.badRequest("selector mixes authentication and signing key usages"))
    }
    return .success(qualified ? .qualified : .authentication)
  }

  /// The strict key-algorithm selector gate (v1.3 §2.7.2).
  internal static func selectorRefusal(
    _ payload: ScsBeginDocument,
    keyAlgorithm: ScsKeyAlgorithm
  ) -> ScsTransactionError? {
    guard
      payload.strictKeyPolicy,
      let algorithms = payload.selector?.keyalgorithms,
      !algorithms.isEmpty
    else {
      return nil
    }
    let name =
      switch keyAlgorithm {
      case .ecdsa:
        "ec"

      case .rsa:
        "rsa"
      }
    let accepted = algorithms.contains { algorithm in
      algorithm.caseInsensitiveCompare(name) == .orderedSame
    }
    return accepted ? nil : .badRequest("strict key policy excludes the available card key")
  }

  /// Decodes one base64url JSON segment.
  internal static func decodeSegment<Document: Decodable>(
    _ encoded: String,
    as type: Document.Type,
    label: String
  ) -> Result<Document, ScsTransactionError> {
    guard let data = Base64Url.decode(encoded) else {
      return .failure(.badRequest("\(label) is not base64url"))
    }
    guard let document = try? JSONDecoder().decode(type, from: data) else {
      return .failure(.badRequest("\(label) is not valid JSON"))
    }
    return .success(document)
  }

  /// Encodes one JSON value as a base64url segment.
  internal static func encodeSegment<Document: Encodable>(
    _ document: Document
  ) -> Result<String, ScsTransactionError> {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(document) else {
      return .failure(.internalError("serialize transaction response"))
    }
    return .success(Base64Url.encode(data))
  }

  /// The response JWT's key identifier: the leaf certificate's SHA-1,
  /// upper-case hex, as the specification prints it.
  internal static func keyIdentifier(chain: [String]) -> String {
    let leaf = chain.first.flatMap { encoded in Data(base64Encoded: encoded) } ?? Data()
    return Insecure.SHA1.hash(data: leaf)
      .map { byte in String(format: "%02X", byte) }
      .joined()
  }
}
