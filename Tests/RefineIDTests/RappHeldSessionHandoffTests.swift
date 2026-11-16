// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import Testing

/// Verifies strict request/answer validation on the RAPP local handoff boundary (STPA CC-71).
@Suite
internal struct RappHeldSessionHandoffTests {
  /// A 16-byte pair identifier, as RAPP derives them.
  private static let pairID = Data("pair-identifier!".utf8)

  /// A synthetic digest within the CryptoTokenKit digest bound.
  private static let digest = Data("digest to sign".utf8)

  /// Synthetic certificate or signature bytes.
  private static let bytes = Data("answer bytes".utf8)

  /// Every answer the app can return over the local handoff channel.
  private static var answers: [RappHeldSessionHandoff.Answer] {
    var all: [RappHeldSessionHandoff.Answer] = [
      .response(.authenticationCertificate(bytes)),
      .response(.signature(bytes)),
      .response(.signatureCertificate(bytes)),
      .failed(.noActivePair), .failed(.noSelectedPair), .failed(.peerNotFound),
      .failed(.protocolFailure), .failed(.timedOut), .failed(.transport),
      .failed(.unexpectedResult),
    ]
    all += RappTerminalReason.allCases.map { .failed(.terminal($0)) }
    return all
  }

  /// Every key-profile and algorithm combination round-trips and enforces `"macOS CryptoTokenKit"`.
  @Test
  internal func requestsRoundTripAndEnforceServerDisplayContext() throws {
    for keyProfile in RappOperationDriver.KeyProfile.allCases {
      for algorithm in RappOperationDriver.SignatureAlgorithm.allCases {
        let request = try #require(
          RappHeldSessionHandoff.Request(
            pairID: Self.pairID,
            keyProfile: keyProfile,
            algorithm: algorithm,
            digest: Self.digest
          )
        )
        let encoded = try #require(request.encoded())
        let decoded = try #require(RappHeldSessionHandoff.Request(encoded: encoded))
        #expect(decoded == request)
        #expect(
          decoded.operation
            == .browserAuthentication(
              displayContext: RappHeldSessionHandoff.cryptoTokenKitDisplayContext,
              keyProfile: keyProfile,
              algorithm: algorithm,
              digest: Self.digest
            )
        )
      }
    }
  }

  /// Every answer variant round-trips cleanly.
  @Test
  internal func answersRoundTrip() throws {
    for answer in Self.answers {
      let encoded = try #require(answer.encoded())
      #expect(RappHeldSessionHandoff.Answer(encoded: encoded) == answer)
    }
  }

  /// Missing `pairID`, invalid `pairID` lengths, and empty or oversized digests are rejected.
  @Test
  internal func invalidPairIdOrDigestBoundsAreRefused() throws {
    #expect(
      RappHeldSessionHandoff.Request(
        pairID: Data("short".utf8),
        keyProfile: .ecdsaP256,
        algorithm: .ecdsaSHA256,
        digest: Self.digest
      ) == nil
    )
    #expect(
      RappHeldSessionHandoff.Request(
        pairID: Self.pairID,
        keyProfile: .ecdsaP256,
        algorithm: .ecdsaSHA256,
        digest: Data()
      ) == nil
    )
    let oversizedDigest = Data(
      repeating: 1,
      count: RappHeldSessionHandoff.maximumDigestByteCount + 1
    )
    #expect(
      RappHeldSessionHandoff.Request(
        pairID: Self.pairID,
        keyProfile: .ecdsaP256,
        algorithm: .ecdsaSHA256,
        digest: oversizedDigest
      ) == nil
    )

    let missingPair = try PropertyListSerialization.data(
      fromPropertyList: [
        "operation": "browserAuthentication",
        "keyProfile": "ecdsaP256",
        "algorithm": "ecdsaSHA256",
        "digest": Self.digest,
      ],
      format: .binary,
      options: 0
    )
    #expect(RappHeldSessionHandoff.Request(encoded: missingPair) == nil)
  }

  /// Disallowed operations (`documentSigning`, certificate reads) and spoofed `context` keys fail closed.
  @Test
  internal func disallowedOperationsAndInjectedContextKeysAreRefused() throws {
    let injectedContext = try PropertyListSerialization.data(
      fromPropertyList: [
        "operation": "browserAuthentication",
        "pair": Self.pairID,
        "context": "https://spoofed.example",
        "keyProfile": "ecdsaP256",
        "algorithm": "ecdsaSHA256",
        "digest": Self.digest,
      ],
      format: .binary,
      options: 0
    )
    #expect(RappHeldSessionHandoff.Request(encoded: injectedContext) == nil)

    let documentSigning = try PropertyListSerialization.data(
      fromPropertyList: [
        "operation": "documentSigning",
        "pair": Self.pairID,
        "keyProfile": "ecdsaP256",
        "algorithm": "ecdsaSHA256",
        "digest": Self.digest,
      ],
      format: .binary,
      options: 0
    )
    #expect(RappHeldSessionHandoff.Request(encoded: documentSigning) == nil)

    let emptyAnswer = try PropertyListSerialization.data(
      fromPropertyList: ["answer": "response", "response": "signature", "bytes": Data()],
      format: .binary,
      options: 0
    )
    #expect(RappHeldSessionHandoff.Answer(encoded: emptyAnswer) == nil)
    #expect(RappHeldSessionHandoff.Answer(encoded: Data("not a list".utf8)) == nil)
  }
}
