// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Routes one assembled SCS request to its handler and builds the
/// full HTTP response bytes.
///
/// The surface is the DVV SCS specification v1.3: `GET /version`,
/// `POST /sign` (`application/json` or `application/jwt`), and CORS
/// preflights on those two paths. Non-`https://` `Origin` headers are
/// refused before any card or transaction work (v1.3 §2.1).
public enum ScsDispatcher {
  /// The one TCP port the specification names (v1.3 §2.2), for the
  /// platform listener to bind.
  public static let port = ScsValues.port

  /// Dispatches one request and answers the response bytes.
  public static func dispatch(
    request: ScsHttpRequest,
    body: Data,
    backend: any ScsSigningBackend,
    transactions: ScsTransactionManager
  ) -> Data {
    if let origin = request.origin,
      let refusal = ScsOriginPolicy.refusal(forPresentOrigin: origin)
    {
      if request.method == "POST", request.path == "/sign" {
        return signError(
          reasonCode: ScsValues.reasonForbidden,
          reasonText: "Forbidden: " + refusal,
          origin: nil
        )
      }
      return ScsHttpResponse.text(
        status: ScsValues.httpForbidden,
        body: "Forbidden: " + refusal,
        origin: nil
      )
    }
    switch (request.method, request.path) {
    case ("OPTIONS", "/version"), ("OPTIONS", "/sign"):
      return ScsHttpResponse.preflight(origin: request.origin)

    case ("GET", "/version"):
      return ScsHttpResponse.json(
        status: ScsValues.httpOk,
        body: Self.encoded(ScsVersionDocument.current),
        origin: request.origin
      )

    case ("POST", "/sign"):
      return sign(request: request, body: body, backend: backend, transactions: transactions)

    default:
      return ScsHttpResponse.text(
        status: ScsValues.httpNotFound, body: "Not Found", origin: request.origin)
    }
  }

  /// Answer returned when a second `POST /sign` arrives while one is
  /// already awaiting holder approval or card execution.
  public static func busySignResponse(origin: String?) -> Data {
    signError(
      reasonCode: ScsValues.reasonForbidden,
      reasonText: "Forbidden: another signature request is already active",
      origin: origin
    )
  }

  private static func encoded<Document: Encodable>(_ document: Document) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(document) else {
      return Data()
    }
    return data
  }

  private static func signError(
    reasonCode: Int,
    reasonText: String,
    origin: String?
  ) -> Data {
    ScsHttpResponse.json(
      status: ScsValues.httpOk,
      body: Self.encoded(
        ScsSignResponseDocument.failed(reasonCode: reasonCode, reasonText: reasonText)),
      origin: origin
    )
  }

  private static func sign(
    request: ScsHttpRequest,
    body: Data,
    backend: any ScsSigningBackend,
    transactions: ScsTransactionManager
  ) -> Data {
    switch request.contentTypeEssence {
    case "application/jwt":
      return signTransaction(
        request: request, body: body, backend: backend, transactions: transactions)

    case "application/json":
      guard
        let document = try? JSONDecoder().decode(ScsSignRequestDocument.self, from: body)
      else {
        return signError(
          reasonCode: ScsValues.reasonBadRequest,
          reasonText: "Bad request: invalid JSON",
          origin: request.origin
        )
      }
      return signJson(document: document, origin: request.origin, backend: backend)

    default:
      return signError(
        reasonCode: ScsValues.reasonBadRequest,
        reasonText: "Bad request: Content-Type must be application/json or application/jwt",
        origin: request.origin
      )
    }
  }

  private static func signTransaction(
    request: ScsHttpRequest,
    body: Data,
    backend: any ScsSigningBackend,
    transactions: ScsTransactionManager
  ) -> Data {
    let separators = body.count { byte in byte == UInt8(ascii: ".") }
    let outcome: Result<String, ScsTransactionError>
    switch separators {
    case ScsValues.jwsSegmentCount - 1:
      outcome = transactions.begin(
        compactJws: body, origin: request.origin, at: Date(), backend: backend)

    case ScsValues.jweSegmentCount - 1:
      outcome = transactions.execute(
        compactJwe: body, origin: request.origin, backend: backend)

    default:
      return signError(
        reasonCode: ScsValues.reasonBadRequest,
        reasonText: "Bad request: JWT body is not compact JWS or JWE",
        origin: request.origin
      )
    }
    switch outcome {
    case .success(let compact):
      return ScsHttpResponse.jwt(compact, origin: request.origin)

    case .failure(let error):
      return signError(
        reasonCode: error.code, reasonText: error.message, origin: request.origin)
    }
  }

  private static func signJson(
    document: ScsSignRequestDocument,
    origin: String?,
    backend: any ScsSigningBackend
  ) -> Data {
    guard let raw = Data(base64Encoded: document.content) else {
      return signError(
        reasonCode: ScsValues.reasonBadRequest,
        reasonText: "Bad request: content not base64",
        origin: origin
      )
    }
    if document.contentType == "digest" {
      return signError(
        reasonCode: ScsValues.reasonNotImplemented,
        reasonText: "Not Implemented: the card hashes content itself; use contentType \"data\"",
        origin: origin
      )
    }
    guard document.contentType == "data" else {
      return signError(
        reasonCode: ScsValues.reasonBadRequest,
        reasonText: "Bad request: unsupported contentType",
        origin: origin
      )
    }
    let purpose = document.purpose
    if purpose == .authentication,
      let refusal = ScsAuthenticationChallenge.refusal(content: raw, origin: origin)
    {
      return signError(
        reasonCode: ScsValues.reasonForbidden,
        reasonText: "Forbidden: " + refusal,
        origin: origin
      )
    }
    do {
      let signature = try backend.sign(
        ScsSignRequest(purpose: purpose, hash: .sha256, data: raw, origin: origin))
      let response = ScsSignResponseDocument.ok(
        signature: signature.base64EncodedString(),
        signatureAlgorithm: backend.keyAlgorithm(for: purpose).scsName(hash: .sha256),
        chain: backend.certificateChain(for: purpose).map { certificate in
          certificate.base64EncodedString()
        }
      )
      return ScsHttpResponse.json(
        status: ScsValues.httpOk, body: Self.encoded(response), origin: origin)
    } catch {
      let wrapped = ScsTransactionError.wrapping(error)
      return signError(
        reasonCode: wrapped.code, reasonText: wrapped.message, origin: origin)
    }
  }
}
