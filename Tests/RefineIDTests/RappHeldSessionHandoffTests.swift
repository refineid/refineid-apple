// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import RappEngine
import Testing

/// What the RAPP token extension hands the app, and what the app answers,
/// read back at one border (STPA CC-71).
@Suite
internal struct RappHeldSessionHandoffTests {
  /// A 16-byte pair identifier, as RAPP derives them.
  private static let pairID = Data("pair-identifier!".utf8)

  /// A synthetic digest; the border carries it, the engine checks it.
  private static let digest = Data("digest to sign".utf8)

  /// Synthetic certificate or signature bytes.
  private static let bytes = Data("answer bytes".utf8)

  /// Every operation the extension can hand over.
  private static var operations: [RappRequesterOperation] {
    var all: [RappRequesterOperation] = [.readAuthenticationCertificate, .readSignatureCertificate]
    for keyProfile in RappOperationDriver.KeyProfile.allCases {
      for algorithm in RappOperationDriver.SignatureAlgorithm.allCases {
        all.append(
          .browserAuthentication(
            displayContext: "macOS CryptoTokenKit", keyProfile: keyProfile, algorithm: algorithm,
            digest: digest))
        all.append(
          .documentSigning(
            documentName: "contract.pdf", keyProfile: keyProfile, algorithm: algorithm,
            digest: digest))
      }
    }
    return all
  }

  /// Every answer the app can give.
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

  @Test("Every operation reads back as itself, with and without a pairing")
  internal func requestsRoundTrip() throws {
    for operation in Self.operations {
      for pair in [Self.pairID, nil] {
        let request = RappHeldSessionHandoff.Request(pairID: pair, operation: operation)
        let encoded = try #require(request.encoded())
        #expect(RappHeldSessionHandoff.Request(encoded: encoded) == request)
      }
    }
  }

  @Test("Every answer reads back as itself")
  internal func answersRoundTrip() throws {
    for answer in Self.answers {
      let encoded = try #require(answer.encoded())
      #expect(RappHeldSessionHandoff.Answer(encoded: encoded) == answer)
    }
  }

  @Test("A pair identifier of another length is refused")
  internal func wrongPairLengthIsRefused() throws {
    let request = RappHeldSessionHandoff.Request(
      pairID: Data("short".utf8), operation: .readAuthenticationCertificate)
    let encoded = try #require(request.encoded())
    #expect(RappHeldSessionHandoff.Request(encoded: encoded) == nil)
  }

  @Test("A message that names nothing known is refused")
  internal func strangersAreRefused() throws {
    let unknown = try PropertyListSerialization.data(
      fromPropertyList: ["operation": "signEverything"], format: .binary, options: 0)
    #expect(RappHeldSessionHandoff.Request(encoded: unknown) == nil)
    let noDigest = try PropertyListSerialization.data(
      fromPropertyList: [
        "operation": "browserAuthentication", "context": "site",
        "keyProfile": "ecdsaP256", "algorithm": "ecdsaSHA256",
      ],
      format: .binary, options: 0)
    #expect(RappHeldSessionHandoff.Request(encoded: noDigest) == nil)
    let emptyAnswer = try PropertyListSerialization.data(
      fromPropertyList: ["answer": "response", "response": "signature", "bytes": Data()],
      format: .binary, options: 0)
    #expect(RappHeldSessionHandoff.Answer(encoded: emptyAnswer) == nil)
    #expect(RappHeldSessionHandoff.Answer(encoded: Data("not a list".utf8)) == nil)
  }
}
