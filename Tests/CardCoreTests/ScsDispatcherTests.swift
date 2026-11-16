// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// The JSON SCS surface end to end over a scripted backend: version,
/// sign, HTTPS origin enforcement, preflighted content types, scoped
/// OPTIONS routes, and sanitized error responses.
@Suite
internal struct ScsDispatcherTests {
  private struct SecretInternalError: Error, CustomStringConvertible {
    var description: String { "secret-reader-path-and-apdu-detail" }
  }

  private static let origin = "https://dvv.fineid.fi"

  private func backend() -> ScriptedScsBackend {
    ScriptedScsBackend(
      chain: [Data([0x30, 0x03, 0x02, 0x01, 0x07])],
      algorithm: .rsa,
      signature: Data(repeating: 0xAB, count: 384)
    )
  }

  private func dispatch(
    request: ScsHttpRequest,
    body: Data,
    backend: ScriptedScsBackend
  ) -> (status: String, json: [String: Any]) {
    let response = ScsDispatcher.dispatch(
      request: request,
      body: body,
      backend: backend,
      transactions: ScsTransactionManager()
    )
    let text = String(data: response, encoding: .utf8) ?? ""
    let statusLine = text.components(separatedBy: "\r\n").first ?? ""
    let bodyText = text.components(separatedBy: "\r\n\r\n").last ?? ""
    let json =
      (try? JSONSerialization.jsonObject(with: Data(bodyText.utf8))) as? [String: Any] ?? [:]
    return (statusLine, json)
  }

  private func head(
    method: String,
    path: String,
    origin: String?,
    contentType: String?,
    bodyLength: Int
  ) -> ScsHttpRequest {
    ScsHttpRequest(
      method: method,
      path: path,
      origin: origin,
      contentType: contentType,
      bodyLength: bodyLength
    )
  }

  private func signBody(
    content: Data,
    contentType: String,
    keyusages: [String]
  ) -> Data {
    let document = ScsSignRequestDocument(
      content: content.base64EncodedString(),
      contentType: contentType,
      selector: keyusages.isEmpty
        ? nil
        : ScsSignRequestDocument.Selector(keyusages: keyusages),
      hashAlgorithm: nil,
      signatureType: nil
    )
    return (try? JSONEncoder().encode(document)) ?? Data()
  }

  private func challenge() -> Data {
    Data("\(Self.origin);\(String(repeating: "a1b2c3d4", count: 8))".utf8)
  }

  @Test
  internal func versionAndScopedPreflightsBehavePerSpec() {
    let (status, json) = dispatch(
      request: head(
        method: "GET", path: "/version", origin: Self.origin, contentType: nil, bodyLength: 0),
      body: Data(),
      backend: backend()
    )
    #expect(status == "HTTP/1.1 200 OK")
    #expect(json["version"] as? String == "1.3")
    #expect(json["signatureTypes"] as? String == "signature,cms-pades")
    #expect(json["hashAlgorithms"] as? String == "SHA256,SHA384,SHA512")
    #expect(json["selectorAvailable"] as? Bool == true)

    for served in ["/version", "/sign"] {
      let (preflightStatus, _) = dispatch(
        request: head(
          method: "OPTIONS", path: served, origin: Self.origin, contentType: nil, bodyLength: 0),
        body: Data(),
        backend: backend()
      )
      #expect(preflightStatus == "HTTP/1.1 200 OK")
    }
    let (unknownPreflight, _) = dispatch(
      request: head(
        method: "OPTIONS", path: "/nowhere", origin: Self.origin, contentType: nil, bodyLength: 0),
      body: Data(),
      backend: backend()
    )
    #expect(unknownPreflight == "HTTP/1.1 404 Not Found")
  }

  @Test
  internal func httpOriginIsRejectedBeforeTouchingBackend() {
    let scripted = backend()
    let body = signBody(
      content: Data("document".utf8),
      contentType: "data",
      keyusages: ["nonRepudiation"]
    )
    let (signStatus, signJson) = dispatch(
      request: head(
        method: "POST",
        path: "/sign",
        origin: "http://dvv.fineid.fi",
        contentType: "application/json",
        bodyLength: body.count
      ),
      body: body,
      backend: scripted
    )
    #expect(signStatus == "HTTP/1.1 200 OK")
    #expect(signJson["reasonCode"] as? Int == 403)
    #expect((signJson["reasonText"] as? String)?.contains("http") == true)
    #expect(scripted.signedData.isEmpty)

    let (versionStatus, _) = dispatch(
      request: head(
        method: "GET",
        path: "/version",
        origin: "http://dvv.fineid.fi",
        contentType: nil,
        bodyLength: 0
      ),
      body: Data(),
      backend: scripted
    )
    #expect(versionStatus == "HTTP/1.1 403 Forbidden")
  }

  @Test
  internal func signRequiresPreflightedContentTypeEssence() {
    let scripted = backend()
    let body = signBody(
      content: Data("doc".utf8),
      contentType: "data",
      keyusages: ["nonRepudiation"]
    )
    for unpreflighted in [
      nil,
      "text/plain",
      "text/plain; x=application/jwt",
      "application/x-www-form-urlencoded",
      "multipart/form-data; boundary=abc",
    ] {
      let (_, json) = dispatch(
        request: head(
          method: "POST",
          path: "/sign",
          origin: Self.origin,
          contentType: unpreflighted,
          bodyLength: body.count
        ),
        body: body,
        backend: scripted
      )
      #expect(json["reasonCode"] as? Int == 400)
    }
    #expect(scripted.signedData.isEmpty)

    let (_, charsetJson) = dispatch(
      request: head(
        method: "POST",
        path: "/sign",
        origin: Self.origin,
        contentType: "application/json; charset=utf-8",
        bodyLength: body.count
      ),
      body: body,
      backend: scripted
    )
    #expect(charsetJson["status"] as? String == "ok")
  }

  @Test
  internal func authenticationAndQualifiedSignFlowsAndChallengeBounds() {
    let scripted = backend()
    let authBody = signBody(content: challenge(), contentType: "data", keyusages: [])
    let (status, json) = dispatch(
      request: head(
        method: "POST",
        path: "/sign",
        origin: Self.origin,
        contentType: "application/json",
        bodyLength: authBody.count
      ),
      body: authBody,
      backend: scripted
    )
    #expect(status == "HTTP/1.1 200 OK")
    #expect(json["status"] as? String == "ok")
    #expect(json["signatureAlgorithm"] as? String == "SHA256withRSA")
    #expect(scripted.signedPurposes == [.authentication])

    let forgedThreePart = Data(
      "\(Self.origin);\(String(repeating: "a1b2c3d4", count: 8));forgedServerKey".utf8)
    let forgedBody = signBody(content: forgedThreePart, contentType: "data", keyusages: [])
    let (_, forgedJson) = dispatch(
      request: head(
        method: "POST",
        path: "/sign",
        origin: Self.origin,
        contentType: "application/json",
        bodyLength: forgedBody.count
      ),
      body: forgedBody,
      backend: backend()
    )
    #expect(forgedJson["reasonCode"] as? Int == 403)
  }

  @Test
  internal func refusalsNeverLeakInternalErrorStrings() {
    final class ThrowingBackend: ScsSigningBackend {
      func certificateChain(for _: ScsSignPurpose) -> [Data] { [Data([0x30, 0x00])] }
      func keyAlgorithm(for _: ScsSignPurpose) -> ScsKeyAlgorithm { .rsa }
      func sign(_: ScsSignRequest) throws -> Data { throw SecretInternalError() }
    }

    let request = head(
      method: "POST",
      path: "/sign",
      origin: Self.origin,
      contentType: "application/json",
      bodyLength: 0
    )
    let response = ScsDispatcher.dispatch(
      request: request,
      body: signBody(
        content: Data("doc".utf8),
        contentType: "data",
        keyusages: ["nonRepudiation"]
      ),
      backend: ThrowingBackend(),
      transactions: ScsTransactionManager()
    )
    let text = String(data: response, encoding: .utf8) ?? ""
    #expect(!text.contains("secret-reader-path"))
    #expect(text.contains("\"reasonCode\":500"))
    #expect(text.contains("internal signing error"))
  }
}
