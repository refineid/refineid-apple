// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import CryptoKit
  import Foundation
  import Security
  import Testing

  @testable import RefineID

  /// A phone's signature reaches CMS and Security.framework as DER whichever
  /// form the phone sent (RAPP v26.10.9 section 9.2).
  @Suite
  internal struct RemoteSignatureFormatTests {
    private struct Fixture {
      let key: P384.Signing.PrivateKey
      let publicKey: SecKey
      let request: SignRequest
    }

    /// The signed message; P-384 signing hashes it with SHA-384, which is
    /// the request digest.
    private static let message = Data("RAPP".utf8)

    private static func fixture() throws -> Fixture {
      let key = P384.Signing.PrivateKey()
      let publicKey = try #require(
        SecKeyCreateWithData(
          key.publicKey.x963Representation as CFData,
          [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
          ] as CFDictionary,
          nil))
      let digest = Data(SHA384.hash(data: Self.message))
      let request = try #require(CardKeyProfile.ecdsaP384.qualifiedDocumentRequest(digest: digest))
      return Fixture(key: key, publicKey: publicKey, request: request)
    }

    @Test
    internal func rawSignatureIsConvertedToDer() throws {
      let fixture = try Self.fixture()
      let signature = try fixture.key.signature(for: Self.message)
      let verified = try #require(
        fixture.request.verifiedRemoteSignature(
          signature.rawRepresentation, from: fixture.publicKey))
      #expect(verified == signature.derRepresentation)
    }

    @Test
    internal func derFromAnEarlierPhoneIsAccepted() throws {
      let fixture = try Self.fixture()
      let signature = try fixture.key.signature(for: Self.message)
      #expect(
        fixture.request.verifiedRemoteSignature(
          signature.derRepresentation, from: fixture.publicKey)
          == signature.derRepresentation)
    }

    @Test
    internal func signatureFromAnotherKeyIsRefused() throws {
      let fixture = try Self.fixture()
      let other = try P384.Signing.PrivateKey().signature(for: Self.message)
      #expect(
        fixture.request.verifiedRemoteSignature(other.rawRepresentation, from: fixture.publicKey)
          == nil)
    }
  }

#endif
