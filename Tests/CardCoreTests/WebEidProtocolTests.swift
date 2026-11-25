// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoKit
import Foundation
import Security
import Testing

/// Unit tests covering the Web eID v2.x protocol parser and cryptographic
/// double-hash and IEEE P1363 signature verification.
@Suite("Web eID Protocol and Cryptography")
internal struct WebEidProtocolTests {
  // MARK: Nested Types

  private enum Fixtures {
    static let validOrigin = "https://www.eesti.ee"
    static let validOriginWithPort = "https://tara.ria.ee:8443"
    static let appVersion = "26.11.25"
    static let nonceCharacter: Character = "A"
    static let nonAsciiCharacter: Character = "ä"
    static let sampleByteValue = UInt8(ascii: "0")
    static let tamperMask = UInt8.max
    static let certificatePlaceholderLength = 4
    static let p256KeyBitSize = 256
    static let p384KeyBitSize = 384
    static let validChallengeNonce = String(
      repeating: Self.nonceCharacter,
      count: WebEidValues.minimumChallengeNonceLength
    )
    static let shortChallengeNonce = String(
      repeating: Self.nonceCharacter,
      count: WebEidValues.minimumChallengeNonceLength - 1
    )
    static let oversizedChallengeNonce = String(
      repeating: Self.nonceCharacter,
      count: WebEidValues.maximumChallengeNonceLength + 1
    )
    static let crlfOversizedChallengeNonce =
      String(
        repeating: Self.nonceCharacter,
        count: WebEidValues.maximumChallengeNonceLength - 1
      ) + "\r\n"
    static let nonAsciiChallengeNonce =
      String(
        repeating: Self.nonceCharacter,
        count: WebEidValues.minimumChallengeNonceLength - 1
      ) + String(Self.nonAsciiCharacter)
    static let placeholderCertificate = Data(
      repeating: Self.sampleByteValue,
      count: Self.certificatePlaceholderLength
    )
  }

  // MARK: Static Functions

  private static func secKey(fromX963PublicKey x963: Data, bitSize: Int) throws -> SecKey {
    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
      kSecAttrKeySizeInBits as String: bitSize,
    ]
    var unmanagedError: Unmanaged<CFError>?
    guard
      let key = SecKeyCreateWithData(x963 as CFData, attributes as CFDictionary, &unmanagedError)
    else {
      throw unmanagedError?.takeRetainedValue()
        ?? NSError(domain: "WebEidProtocolTests", code: bitSize)
    }
    return key
  }

  // MARK: Functions

  @Test("HTTPS origins accept host and optional port and reject paths or HTTP")
  internal func originValidation() {
    #expect(WebEidOrigin(Fixtures.validOrigin)?.value == Fixtures.validOrigin)
    #expect(WebEidOrigin(Fixtures.validOriginWithPort)?.value == Fixtures.validOriginWithPort)

    let invalidOrigins = [
      "",
      "http://www.eesti.ee",
      "https://www.eesti.ee/",
      "https://www.eesti.ee/login",
      "https://www.eesti.ee?next=1",
      "https://www.eesti.ee#section",
      "https://user@www.eesti.ee",
      "file:///tmp/page.html",
    ]
    for candidate in invalidOrigins {
      #expect(WebEidOrigin(candidate) == nil)
    }
  }

  @Test("Command parser accepts valid status, authenticate, certificate, and sign payloads")
  internal func commandParsingValid() throws {
    let origin = try #require(WebEidOrigin(Fixtures.validOrigin))
    #expect(try WebEidCommand.parse(dictionary: ["command": "status"]) == .status)

    let auth = try WebEidCommand.parse(dictionary: [
      "command": "authenticate",
      "arguments": [
        "origin": Fixtures.validOrigin,
        "challengeNonce": Fixtures.validChallengeNonce,
        "lang": "et",
      ],
    ])
    #expect(
      auth
        == .authenticate(origin: origin, challengeNonce: Fixtures.validChallengeNonce, lang: "et")
    )

    let cert = try WebEidCommand.parse(dictionary: [
      "command": "get-signing-certificate",
      "arguments": ["origin": Fixtures.validOrigin],
    ])
    #expect(cert == .getSigningCertificate(origin: origin, lang: nil))

    let digest = Data(SHA384.hash(data: Data(Fixtures.validOrigin.utf8)))
    let sign = try WebEidCommand.parse(dictionary: [
      "command": "sign",
      "arguments": [
        "origin": Fixtures.validOrigin,
        "certificate": Fixtures.placeholderCertificate.base64EncodedString(),
        "hash": digest.base64EncodedString(),
        "hashFunction": WebEidHashFunction.sha384.rawValue,
      ],
    ])
    let expectedSign = WebEidCommand.SignRequest(
      origin: origin,
      certificateDER: Fixtures.placeholderCertificate,
      hash: digest,
      hashFunction: .sha384,
      lang: nil
    )
    #expect(sign == .sign(expectedSign))
  }

  @Test("Command parser rejects invalid nonces, origins, and mismatched digest lengths")
  internal func commandParsingRejectsInvalidInputs() {
    let invalidNonces = [
      Fixtures.shortChallengeNonce,
      Fixtures.oversizedChallengeNonce,
      Fixtures.crlfOversizedChallengeNonce,
      Fixtures.nonAsciiChallengeNonce,
    ]
    for nonce in invalidNonces {
      #expect(throws: WebEidError.self) {
        _ = try WebEidCommand.parse(dictionary: [
          "command": "authenticate",
          "arguments": [
            "origin": Fixtures.validOrigin,
            "challengeNonce": nonce,
          ],
        ])
      }
    }

    let sha256Digest = Data(SHA256.hash(data: Data(Fixtures.validOrigin.utf8)))
    #expect(throws: WebEidError.self) {
      _ = try WebEidCommand.parse(dictionary: [
        "command": "sign",
        "arguments": [
          "origin": Fixtures.validOrigin,
          "certificate": Fixtures.placeholderCertificate.base64EncodedString(),
          "hash": sha256Digest.base64EncodedString(),
          "hashFunction": WebEidHashFunction.sha384.rawValue,
        ],
      ])
    }
  }

  @Test("Authentication digest matches Web eID double-hash H(H(origin) || H(nonce))")
  internal func authenticationDoubleHashMatchesSpec() throws {
    let origin = try #require(WebEidOrigin(Fixtures.validOrigin))
    let expectedPayload =
      Data(SHA384.hash(data: Data(origin.value.utf8)))
      + Data(SHA384.hash(data: Data(Fixtures.validChallengeNonce.utf8)))
    let expectedDigest = Data(SHA384.hash(data: expectedPayload))

    #expect(
      WebEidCrypto.authenticationSignedPayload(
        origin: origin,
        challengeNonce: Fixtures.validChallengeNonce,
        hashFunction: .sha384
      ) == expectedPayload
    )
    #expect(
      WebEidCrypto.authenticationDigest(
        origin: origin,
        challengeNonce: Fixtures.validChallengeNonce,
        hashFunction: .sha384
      ) == expectedDigest
    )
  }

  @Test("Raw P-384 signatures verify locally, encode token fields, and reject tampered bytes")
  internal func rawP384SignatureRoundTripVerification() throws {
    let origin = try #require(WebEidOrigin(Fixtures.validOrigin))
    let key = P384.Signing.PrivateKey()
    let publicKey = try Self.secKey(
      fromX963PublicKey: key.publicKey.x963Representation,
      bitSize: Fixtures.p384KeyBitSize
    )
    let payload = try #require(
      WebEidCrypto.authenticationSignedPayload(
        origin: origin, challengeNonce: Fixtures.validChallengeNonce, hashFunction: .sha384
      )
    )
    let digest = try #require(
      WebEidCrypto.authenticationDigest(
        origin: origin, challengeNonce: Fixtures.validChallengeNonce, hashFunction: .sha384
      )
    )
    let signature = try key.signature(for: payload).rawRepresentation
    #expect(
      WebEidCrypto.verifyRawSignature(
        signature, overDigest: digest, hashFunction: .sha384, profile: .ecdsaP384,
        publicKey: publicKey
      )
    )

    var tampered = signature
    tampered[tampered.startIndex] ^= Fixtures.tamperMask
    #expect(
      !WebEidCrypto.verifyRawSignature(
        tampered, overDigest: digest, hashFunction: .sha384, profile: .ecdsaP384,
        publicKey: publicKey
      )
    )

    let response = WebEidCrypto.makeAuthenticationResponse(
      certificateDER: Fixtures.placeholderCertificate,
      jwsAlgorithm: WebEidCrypto.authParameters(for: .ecdsaP384).jwsAlgorithm,
      rawSignature: signature,
      appVersion: Fixtures.appVersion
    )
    let dict = response.toDictionary()
    #expect(dict["format"] as? String == WebEidValues.tokenFormat)
    #expect(dict["algorithm"] as? String == WebEidValues.jwsEs384)
    #expect(dict["appVersion"] as? String == WebEidValues.appVersionPrefix + Fixtures.appVersion)
    #expect(dict["signature"] as? String == signature.base64EncodedString())
  }

  @Test("Raw P-256 signatures verify locally over Web eID authentication digests")
  internal func rawP256SignatureRoundTripVerification() throws {
    let origin = try #require(WebEidOrigin(Fixtures.validOrigin))
    let key = P256.Signing.PrivateKey()
    let publicKey = try Self.secKey(
      fromX963PublicKey: key.publicKey.x963Representation,
      bitSize: Fixtures.p256KeyBitSize
    )
    let payload = try #require(
      WebEidCrypto.authenticationSignedPayload(
        origin: origin,
        challengeNonce: Fixtures.validChallengeNonce,
        hashFunction: .sha256
      )
    )
    let digest = try #require(
      WebEidCrypto.authenticationDigest(
        origin: origin,
        challengeNonce: Fixtures.validChallengeNonce,
        hashFunction: .sha256
      )
    )
    let signature = try key.signature(for: payload).rawRepresentation
    #expect(
      WebEidCrypto.verifyRawSignature(
        signature,
        overDigest: digest,
        hashFunction: .sha256,
        profile: .ecdsaP256,
        publicKey: publicKey
      )
    )
  }
}
