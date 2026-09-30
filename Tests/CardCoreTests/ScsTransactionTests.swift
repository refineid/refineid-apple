// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoKit
import Foundation
import Testing

/// The SCS transaction flow over a scripted backend: an ES256-signed
/// begin, key agreement, and the encrypted execute (DVV SCS
/// specification v1.3 §2.7).
@Suite
internal struct ScsTransactionTests {
  /// One relying-service side of a transaction: its certificate,
  /// its signing key, and its agreement key.
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

  private func beginJws(
    _ service: Service,
    keyusages: [String]
  ) -> Data {
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

  /// The transaction key as the relying service derives it from the
  /// begin response.
  private func serviceKey(_ service: Service, beginResponse: String) throws -> SymmetricKey {
    let payloadSegment = beginResponse.components(separatedBy: ".")[1]
    let payload = try #require(Base64Url.decode(payloadSegment))
    let json = try #require(
      try JSONSerialization.jsonObject(with: payload) as? [String: Any])
    #expect(json["status"] as? String == "ok")
    let transaction = try #require(json["transaction"] as? String)
    let transactionDer = try #require(Data(base64Encoded: transaction))
    let scsPublic = try P256.KeyAgreement.PublicKey(derRepresentation: transactionDer)
    let shared = try service.agreement.sharedSecretFromKeyAgreement(with: scsPublic)
    return SymmetricKey(data: shared)
  }

  private func executeJwe(
    key: SymmetricKey,
    payload: [String: Any]
  ) throws -> Data {
    let plaintext = try JSONSerialization.data(withJSONObject: payload)
    let sealed = ScsJsonWebEncryption.encrypt(plaintext: plaintext, key: key)
    return Data(try sealed.get().utf8)
  }

  @Test
  internal func qualifiedCmsRoundTripSignsTheAttributeSet() throws {
    let service = service()
    let scripted = backend()
    let manager = ScsTransactionManager()

    let begun = manager.begin(
      compactJws: beginJws(service, keyusages: ["nonRepudiation"]),
      origin: Self.origin,
      at: Date(),
      backend: scripted
    )
    let beginResponse = try begun.get()
    let key = try serviceKey(service, beginResponse: beginResponse)

    let digest = Data(repeating: 0x11, count: 32)
    let executed = manager.execute(
      compactJwe: try executeJwe(
        key: key,
        payload: [
          "version": "1.3",
          "content": digest.base64EncodedString(),
          "contentType": "digest",
          "hashAlgorithm": "SHA256",
          "signatureType": "cms-pades",
        ]
      ),
      origin: Self.origin,
      backend: scripted
    )
    let responseCompact = try executed.get()
    let opened = ScsJsonWebEncryption.decrypt(
      compact: Data(responseCompact.utf8), key: key)
    let plaintext = try opened.get()
    let json = try #require(
      try JSONSerialization.jsonObject(with: plaintext) as? [String: Any])
    #expect(json["status"] as? String == "ok")
    #expect(json["signatureType"] as? String == "cms-pades")
    #expect(json["signatureAlgorithm"] as? String == "SHA256withRSA")
    let signature = try #require(json["signature"] as? String)
    #expect(Data(base64Encoded: signature) != nil)
    // The begin response was signed first; the CMS attribute SET is
    // the second sign, and its bytes are a DER SET carrying the
    // message digest.
    #expect(scripted.signedData.count == 2)
    let attributes = try #require(scripted.signedData.last)
    #expect(attributes.first == 0x31)
    #expect(attributes.firstRange(of: digest) != nil)
    // Both signs carry the origin, including the one that signs
    // derived CMS attributes: the end user is asked to approve each
    // sign, and the approval names the origin.
    #expect(scripted.signedOrigins == [Self.origin, Self.origin])
  }

  @Test
  internal func boundAuthenticationChallengePassesAndSigns() throws {
    let service = service()
    let scripted = backend()
    let manager = ScsTransactionManager()
    let begun = manager.begin(
      compactJws: beginJws(service, keyusages: []),
      origin: Self.origin,
      at: Date(),
      backend: scripted
    )
    let beginResponse = try begun.get()
    let key = try serviceKey(service, beginResponse: beginResponse)
    let nonce = String(repeating: "a1b2c3d4", count: 8)
    let challenge = "\(Self.origin);\(nonce);\(service.serverKeyB64)"
    let executed = manager.execute(
      compactJwe: try executeJwe(
        key: key,
        payload: [
          "version": "1.3",
          "content": Data(challenge.utf8).base64EncodedString(),
        ]
      ),
      origin: Self.origin,
      backend: scripted
    )
    #expect((try? executed.get()) != nil)
    #expect(scripted.signedPurposes.last == .authentication)
  }

  @Test
  internal func unboundAuthenticationChallengeIsForbidden() throws {
    let service = service()
    let scripted = backend()
    let manager = ScsTransactionManager()
    let begun = manager.begin(
      compactJws: beginJws(service, keyusages: []),
      origin: Self.origin,
      at: Date(),
      backend: scripted
    )
    let beginResponse = try begun.get()
    let key = try serviceKey(service, beginResponse: beginResponse)
    let executed = manager.execute(
      compactJwe: try executeJwe(
        key: key,
        payload: [
          "version": "1.3",
          "content": Data("arbitrary".utf8).base64EncodedString(),
        ]
      ),
      origin: Self.origin,
      backend: scripted
    )
    guard case .failure(let error) = executed else {
      Issue.record("expected a forbidden refusal")
      return
    }
    #expect(error.code == 403)
  }

  @Test
  internal func executeWithoutBeginIsRefused() {
    let outcome = ScsTransactionManager().execute(
      compactJwe: Data("a..b.c.d".utf8),
      origin: Self.origin,
      backend: backend()
    )
    guard case .failure(let error) = outcome else {
      Issue.record("expected a refusal")
      return
    }
    #expect(error.code == 400)
    #expect(error.message.contains("no active transaction"))
  }

  @Test
  internal func executeFromAnotherOriginIsForbidden() throws {
    let service = service()
    let manager = ScsTransactionManager()
    let begun = manager.begin(
      compactJws: beginJws(service, keyusages: ["nonRepudiation"]),
      origin: Self.origin,
      at: Date(),
      backend: backend()
    )
    _ = try begun.get()
    let outcome = manager.execute(
      compactJwe: Data("a..b.c.d".utf8),
      origin: "https://attacker.example",
      backend: backend()
    )
    guard case .failure(let error) = outcome else {
      Issue.record("expected a refusal")
      return
    }
    #expect(error.code == 403)
  }

  @Test
  internal func tamperedBeginSignatureIsForbidden() {
    let service = service()
    // Flip the first character of the signature segment: the last
    // character only feeds discarded base64url padding bits, so the
    // corruption must land on fully significant ones.
    var compact = String(data: beginJws(service, keyusages: []), encoding: .utf8) ?? ""
    let signatureStart = compact.index(after: compact.lastIndex(of: ".") ?? compact.startIndex)
    let original = compact[signatureStart]
    compact.replaceSubrange(
      signatureStart...signatureStart, with: original == "A" ? "B" : "A")
    let outcome = ScsTransactionManager().begin(
      compactJws: Data(compact.utf8),
      origin: Self.origin,
      at: Date(),
      backend: backend()
    )
    guard case .failure(let error) = outcome else {
      Issue.record("expected a refusal")
      return
    }
    #expect(error.code == 403)
  }

  @Test
  internal func expiredServerCertificateIsRefused() {
    let expired = Service(
      material: ScsTestCertificate.make(
        notBefore: "200101000000Z", notAfter: "210101000000Z"),
      agreement: P256.KeyAgreement.PrivateKey()
    )
    let outcome = ScsTransactionManager().begin(
      compactJws: beginJws(expired, keyusages: []),
      origin: Self.origin,
      at: Date(),
      backend: backend()
    )
    guard case .failure(let error) = outcome else {
      Issue.record("expected a refusal")
      return
    }
    #expect(error.message.contains("not currently valid"))
  }
}
