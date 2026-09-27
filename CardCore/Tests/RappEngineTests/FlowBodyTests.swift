// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
//
// Replays the pairing and session message bodies emitted by the reference
// engine. The conformance corpus proves the envelope and the handshake, and
// the transport vectors prove the frames that carry operations, but the
// bodies between them had no golden bytes: an encoding both sides of one
// implementation agree on can still be one no peer accepts.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP flow bodies against the vendored bytes")
internal struct FlowBodyTests {
  private struct Fixtures {
    let inputs: FlowInputs
    let parameters: NegotiatedParameters
    let offered: [ProfileName]
    let nonce: Data
  }

  private static func fixtures(_ corpus: FlowCorpus) throws -> Fixtures {
    let inputs = corpus.fixedInputs
    return Fixtures(
      inputs: inputs,
      parameters: NegotiatedParameters(
        offerHash: try Data(hex: inputs.offerHashHex),
        transportProfile: inputs.transportProfile,
        candidateIdentifier: inputs.candidateIdentifier),
      offered: inputs.offeredProfiles.compactMap { ProfileName(rawValue: $0) },
      nonce: try Data(hex: inputs.readyNonceHex))
  }

  private static func body(_ fields: [String: WireValue]) throws -> String {
    try WireValue.map(fields).encoded().hex
  }

  private static func expected(_ corpus: FlowCorpus, _ name: String) throws -> String {
    guard let vector = corpus.flowMessage.first(where: { $0.name == name }) else {
      throw CorpusError.missingHandshake(name: name)
    }
    return vector.bodyHex
  }

  @Test("The vendored bodies are the current revision")
  internal func vectorIdentity() throws {
    let corpus = try CorpusFile.flow(filePath: #filePath)
    #expect(corpus.format == "fi.refineid.rapp.flow-vectors-v1")
    #expect(corpus.protocolDocumentVersion == "26.9.7.70")
    #expect(corpus.flowMessage.count == 7)
  }

  @Test("Each pairing hello matches the reference engine byte for byte")
  internal func pairingHelloBodies() throws {
    let corpus = try CorpusFile.flow(filePath: #filePath)
    let fixed = try Self.fixtures(corpus)

    let requester = PairingHello(
      parameters: fixed.parameters,
      displayName: fixed.inputs.requesterDisplayName,
      platform: fixed.inputs.requesterPlatform,
      requestedProfiles: fixed.offered)
    #expect(
      try Self.body(requester.body())
        == (try Self.expected(corpus, "requester-hello-with-requested-profiles")))

    let proxy = PairingHello(
      parameters: fixed.parameters,
      displayName: fixed.inputs.proxyDisplayName,
      platform: fixed.inputs.proxyPlatform,
      requestedProfiles: nil)
    #expect(
      try Self.body(proxy.body())
        == (try Self.expected(corpus, "proxy-hello-without-requested-profiles")))
  }

  @Test("A hello omits the requested profiles only for the answering side")
  internal func requestedProfilesAreRoleDependent() throws {
    let corpus = try CorpusFile.flow(filePath: #filePath)
    #expect(
      try Self.expected(corpus, "requester-hello-with-requested-profiles")
        != (try Self.expected(corpus, "proxy-hello-without-requested-profiles")))
  }

  @Test("Each confirmation matches the reference engine byte for byte")
  internal func pairingConfirmBodies() throws {
    let corpus = try CorpusFile.flow(filePath: #filePath)
    let fixed = try Self.fixtures(corpus)
    let cases: [(String, [ProfileName])] = [
      ("confirm-two-profiles", fixed.offered),
      ("confirm-single-profile", [.authentication]),
      ("confirm-three-profiles", [.authentication, .cardStatus, .documentSigning]),
    ]
    for (name, granted) in cases {
      let encodedBody = try Self.body(PairingConfirm(grantedProfiles: granted).body())
      #expect(
        encodedBody == (try Self.expected(corpus, name)), "\(name)")
    }
  }

  @Test("Each session ready matches the reference engine byte for byte")
  internal func sessionReadyBodies() throws {
    let corpus = try CorpusFile.flow(filePath: #filePath)
    let fixed = try Self.fixtures(corpus)
    let cases: [(String, String)] = [
      ("session-ready-fixed-grants-hash", fixed.inputs.grantsHashFixedHex),
      ("session-ready-derived-grants-hash", fixed.inputs.grantsHashDerivedHex),
    ]
    for (name, grantsHashHex) in cases {
      let parameters = SessionParameters(
        transportProfile: fixed.inputs.transportProfile,
        candidateIdentifier: fixed.inputs.candidateIdentifier,
        grantsHash: try Data(hex: grantsHashHex))
      #expect(
        try Self.body(SessionReady(parameters: parameters, nonce: fixed.nonce).body())
          == (try Self.expected(corpus, name)), "\(name)")
    }
  }

  @Test("A ready body carries the grants hash, so a different hash differs")
  internal func readyCarriesTheGrantsHash() throws {
    let corpus = try CorpusFile.flow(filePath: #filePath)
    #expect(
      try Self.expected(corpus, "session-ready-fixed-grants-hash")
        != (try Self.expected(corpus, "session-ready-derived-grants-hash")))
  }

  @Test("The granted set hashes to the reference value")
  internal func grantsHashMatches() throws {
    let corpus = try CorpusFile.flow(filePath: #filePath)
    let fixed = try Self.fixtures(corpus)
    let derived = try RappHashes.grantsHash(profiles: fixed.offered.map(\.rawValue))
    #expect(derived.hex == fixed.inputs.grantsHashDerivedHex)
  }

  @Test("A changed display name changes the bytes")
  internal func changedNameChangesTheBytes() throws {
    let corpus = try CorpusFile.flow(filePath: #filePath)
    let fixed = try Self.fixtures(corpus)
    let altered = PairingHello(
      parameters: fixed.parameters,
      displayName: fixed.inputs.requesterDisplayName + "!",
      platform: fixed.inputs.requesterPlatform,
      requestedProfiles: fixed.offered)
    #expect(
      try Self.body(altered.body())
        != (try Self.expected(corpus, "requester-hello-with-requested-profiles")))
  }
}
