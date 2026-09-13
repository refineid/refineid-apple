// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@Suite("RAPP independent session conformance corpus")
internal struct RappSessionConformanceCorpusTests {
  // MARK: Static Properties

  private static let supportedWireVersion: [UInt16] = [26, 9, 13]

  // MARK: Static Functions

  private static func corpus() throws -> RappSessionConformanceCorpusSupport.SessionCorpus {
    let repository = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let url =
      repository
      .appendingPathComponent("Documentation")
      .appendingPathComponent("rapp-conformance")
      .appendingPathComponent("rapp-v26.9.13.json")
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(
      RappSessionConformanceCorpusSupport.SessionCorpus.self,
      from: Data(contentsOf: url))
  }

  // MARK: Functions

  @Test
  internal func exactDirectionalSequenceAndSessionBindingMatchCorpus() throws {
    let vectors = try Self.corpus().sequenceGuard
    #expect(vectors.count == 6)
    for vector in vectors {
      let guardSessionID = try RappSessionConformanceCorpusSupport.data(
        fromHex: vector.guardSessionIdHex)
      var guardState = RappSessionConformanceCorpusSupport.IndependentSequenceGuard(
        sessionID: guardSessionID)

      for sequence in vector.acceptedSequences {
        #expect(
          guardState.accept(sessionID: guardSessionID, sequence: sequence) == .accepted,
          "\(vector.name): invalid accepted prefix at \(sequence)"
        )
      }

      let incomingSessionID = try RappSessionConformanceCorpusSupport.data(
        fromHex: vector.incomingSessionIdHex)
      #expect(
        guardState.accept(
          sessionID: incomingSessionID,
          sequence: vector.incomingSequence
        ).rawValue == vector.expected,
        "\(vector.name): candidate decision"
      )
      #expect(
        guardState.accept(
          sessionID: guardSessionID,
          sequence: vector.expectedNextReceive
        ) == .accepted,
        "\(vector.name): rejected candidate advanced the guard"
      )
    }
  }

  @Test
  internal func visibleWireVersionRejectsDowngradesAndUnknownUpgrades() throws {
    let vectors = try Self.corpus().wireVersion
    #expect(vectors.count == 9)
    for vector in vectors {
      let decision =
        vector.version == Self.supportedWireVersion
        ? "accepted"
        : "unsupported_version"
      #expect(decision == vector.expected, "\(vector.name): wire version decision")
    }
  }

  @Test
  internal func operationProfilesCannotExceedAuthenticatedPairingGrants() throws {
    let vectors = try Self.corpus().grantEnforcement
    #expect(vectors.count == 3)
    for vector in vectors {
      let decision =
        Set(vector.grantedProfiles).contains(vector.requestedProfile)
        ? "accepted"
        : "profile_not_granted"
      #expect(decision == vector.expected, "\(vector.name): grant decision")
    }
  }
}
