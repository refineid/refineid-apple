// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoKit
import Foundation
import Testing

/// Transaction TTL expiry, `clear()` teardown, and `cms-pades`
/// `contentType == "data"` hashing before CMS attribute construction.
@Suite
internal struct ScsTransactionLifecycleTests {
  private struct Service {
    let material: ScsTestCertificate.Material
    let agreement: P256.KeyAgreement.PrivateKey

    var serverKeyB64: String {
      agreement.publicKey.derRepresentation.base64EncodedString()
    }
  }

  private static let origin = "https://dvv.fineid.fi"

  private func service() -> Service {
    Service(material: ScsTestCertificate.make(), agreement: P256.KeyAgreement.PrivateKey())
  }

  private func backend() -> ScriptedScsBackend {
    ScriptedScsBackend(
      chain: [ScsTestCertificate.make().der],
      algorithm: .rsa,
      signature: Data(repeating: 0xCD, count: 384)
    )
  }

  private func beginJws(_ service: Service, keyusages: [String]) -> Data {
    func segment(_ json: [String: Any]) -> String {
      let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
      return Base64Url.encode(data)
    }
    var payload: [String: Any] = [
      "version": "1.3",
      "serverKey": service.serverKeyB64,
      "serverCert": service.material.der.base64EncodedString(),
    ]
    if !keyusages.isEmpty {
      payload["selector"] = ["keyusages": keyusages]
    }
    let input = segment(["alg": "ES256"]) + "." + segment(payload)
    let signature =
      (try? service.material.key.signature(for: Data(input.utf8)))?.rawRepresentation
      ?? Data()
    return Data((input + "." + Base64Url.encode(signature)).utf8)
  }

  private func serviceKey(_ service: Service, beginResponse: String) throws -> SymmetricKey {
    let payloadSegment = beginResponse.components(separatedBy: ".")[1]
    let payload = try #require(Base64Url.decode(payloadSegment))
    let json = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
    let transaction = try #require(json["transaction"] as? String)
    let transactionDer = try #require(Data(base64Encoded: transaction))
    let scsPublic = try P256.KeyAgreement.PublicKey(derRepresentation: transactionDer)
    let shared = try service.agreement.sharedSecretFromKeyAgreement(with: scsPublic)
    return SymmetricKey(data: shared)
  }

  private func executeJwe(key: SymmetricKey, payload: [String: Any]) throws -> Data {
    let plaintext = try JSONSerialization.data(withJSONObject: payload)
    let sealed = ScsJsonWebEncryption.encrypt(plaintext: plaintext, key: key)
    return Data(try sealed.get().utf8)
  }

  @Test
  internal func cmsPadesWithDataContentHashesDocumentBeforeBuildingSignedAttributes() throws {
    let service = service()
    let scripted = backend()
    let manager = ScsTransactionManager()
    let now = Date()
    let begun = manager.begin(
      compactJws: beginJws(service, keyusages: ["nonRepudiation"]),
      origin: Self.origin,
      at: now,
      backend: scripted
    )
    let beginResponse = try begun.get()
    let key = try serviceKey(service, beginResponse: beginResponse)

    let document = Data("full PDF bytes rather than a precomputed 32-byte digest".utf8)
    let expectedDigest = Data(SHA256.hash(data: document))
    let executed = manager.execute(
      compactJwe: try executeJwe(
        key: key,
        payload: [
          "version": "1.3",
          "content": document.base64EncodedString(),
          "contentType": "data",
          "hashAlgorithm": "SHA256",
          "signatureType": "cms-pades",
        ]
      ),
      origin: Self.origin,
      at: now.addingTimeInterval(5),
      backend: scripted
    )
    _ = try executed.get()
    let attributes = try #require(scripted.signedData.last)
    #expect(attributes.firstRange(of: expectedDigest) != nil)
    #expect(attributes.firstRange(of: document) == nil)
  }

  @Test
  internal func pendingTransactionExpiresAfterTimeToLiveAndEvictsOnNextBegin() throws {
    let service = service()
    let scripted = backend()
    let manager = ScsTransactionManager()
    let start = Date()
    let firstBegun = manager.begin(
      compactJws: beginJws(service, keyusages: ["nonRepudiation"]),
      origin: Self.origin,
      at: start,
      backend: scripted
    )
    let beginResponse = try firstBegun.get()
    let key = try serviceKey(service, beginResponse: beginResponse)
    let jwe = try executeJwe(
      key: key,
      payload: [
        "version": "1.3",
        "content": Data("doc".utf8).base64EncodedString(),
        "contentType": "data",
        "hashAlgorithm": "SHA256",
        "signatureType": "signature",
      ]
    )

    let expiredOutcome = manager.execute(
      compactJwe: jwe,
      origin: Self.origin,
      at: start.addingTimeInterval(61),
      backend: scripted
    )
    guard case .failure(let error) = expiredOutcome else {
      Issue.record("expected expired transaction refusal")
      return
    }
    #expect(error.code == 400)
    #expect(error.message.contains("expired"))

    let secondBegun = manager.begin(
      compactJws: beginJws(service, keyusages: ["nonRepudiation"]),
      origin: Self.origin,
      at: start,
      backend: scripted
    )
    _ = try secondBegun.get()
    let freshAfterExpiry = manager.begin(
      compactJws: beginJws(service, keyusages: ["nonRepudiation"]),
      origin: Self.origin,
      at: start.addingTimeInterval(65),
      backend: scripted
    )
    #expect((try? freshAfterExpiry.get()) != nil)
  }

  @Test
  internal func clearDropsPendingTransactionOnStop() throws {
    let service = service()
    let scripted = backend()
    let manager = ScsTransactionManager()
    let now = Date()
    let begun = manager.begin(
      compactJws: beginJws(service, keyusages: ["nonRepudiation"]),
      origin: Self.origin,
      at: now,
      backend: scripted
    )
    let beginResponse = try begun.get()
    let key = try serviceKey(service, beginResponse: beginResponse)
    manager.clear()

    let jwe = try executeJwe(
      key: key,
      payload: [
        "version": "1.3",
        "content": Data("doc".utf8).base64EncodedString(),
      ]
    )
    let outcome = manager.execute(
      compactJwe: jwe,
      origin: Self.origin,
      at: now.addingTimeInterval(1),
      backend: scripted
    )
    guard case .failure(let error) = outcome else {
      Issue.record("expected cleared transaction to be absent")
      return
    }
    #expect(error.code == 400)
  }
}
