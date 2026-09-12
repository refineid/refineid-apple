// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation
  import Security
  import Testing

  @testable import RefineID

  /// The app's certificate profile must select one exact PDF-signing request.
  @Suite
  internal struct CardKeyProfileDocumentTests {
    @Test
    internal func p384SelectsEcdsaSha384() throws {
      let digest = Data(repeating: 0xA5, count: 48)
      let request = try #require(
        CardKeyProfile.ecdsaP384.qualifiedDocumentRequest(digest: digest)
      )

      #expect(request.algorithm == SigningAlgorithm(hash: .sha384, scheme: .ecdsa))
      #expect(request.digest == digest)
      #expect(request.expectedSignatureLength?.count == 96)
      #expect(request.rawSignatureLength == 96)
      #expect(request.verifyAlgorithm == .ecdsaSignatureDigestX962SHA384)
    }

    @Test
    internal func rsa3072SelectsPkcs1Sha384() throws {
      let digest = Data(repeating: 0xA5, count: 48)
      let request = try #require(
        CardKeyProfile.rsa3072.qualifiedDocumentRequest(digest: digest)
      )

      #expect(
        request.algorithm
          == SigningAlgorithm(hash: .sha384, scheme: .rsaPkcs1)
      )
      #expect(request.digest == digest)
      #expect(request.expectedSignatureLength == nil)
      #expect(request.rawSignatureLength == 384)
      #expect(request.verifyAlgorithm == .rsaSignatureDigestPKCS1v15SHA384)
    }

    @Test
    internal func rsa2048SelectsPkcs1Sha384() throws {
      let digest = Data(repeating: 0xA5, count: 48)
      let request = try #require(
        CardKeyProfile.rsa2048.qualifiedDocumentRequest(digest: digest)
      )

      #expect(
        request.algorithm
          == SigningAlgorithm(hash: .sha384, scheme: .rsaPkcs1)
      )
      #expect(request.digest == digest)
      #expect(request.expectedSignatureLength?.count == 256)
      #expect(request.rawSignatureLength == 256)
      #expect(request.verifyAlgorithm == .rsaSignatureDigestPKCS1v15SHA384)
    }
  }

#endif
