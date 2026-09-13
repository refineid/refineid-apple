// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP wire layer against the vendored corpus")
internal struct WireCorpusTests {
  private static let sampleSession = Data(
    repeating: 0xAA, count: WireLimits.sessionIdentifier)
  private static let sampleDigest = Data(repeating: 0xBB, count: 32)
  @Test("Corpus identity and section sizes are fixed")
  internal func corpusIdentity() throws {
    let corpus = try CorpusFile.conformance(filePath: #filePath)
    #expect(corpus.format == "fi.refineid.rapp.conformance-v1")
    #expect(corpus.protocolDocumentVersion == "26.9.13")
    #expect(corpus.noiseHandshake.count == 2)
  }

  @Test("Every golden deterministic encoding round-trips")
  internal func deterministicCbor() throws {
    for vector in try CorpusFile.conformance(filePath: #filePath).deterministicCBOR {
      let value = vector.value.wireValue
      #expect(try value.encoded().hex == vector.encodedHex, "\(vector.name)")
      let decoded = try decodeDeterministicCbor(try Data(hex: vector.encodedHex))
      #expect(decoded == value, "\(vector.name)")
    }
  }

  @Test("Every malformed encoding is refused with its registered reason")
  internal func rejectedCbor() throws {
    for vector in try CorpusFile.conformance(filePath: #filePath).rejectedCBOR {
      let encoded = try Data(hex: vector.encodedHex)
      let actual = CorpusFailure.name { _ = try decodeDeterministicCbor(encoded) }
      #expect(actual == vector.error, "\(vector.name)")
    }
  }

  @Test("Every malformed envelope is refused with its registered reason")
  internal func rejectedEnvelope() throws {
    for vector in try CorpusFile.conformance(filePath: #filePath).rejectedEnvelope {
      let encoded = try Data(hex: vector.canonicalCBORHex)
      let supported = Set(vector.supportedCritical)
      let actual = CorpusFailure.name {
        try Envelope.decode(encoded).requireSupportedCritical(supported)
      }
      #expect(actual == vector.error, "\(vector.name)")
    }
  }

  @Test("Only the registered wire version is admitted")
  internal func wireVersion() throws {
    for vector in try CorpusFile.conformance(filePath: #filePath).wireVersion {
      let envelope = WireValue.map([
        "version": .array(vector.version.map { .unsigned($0) }),
        "type": .text(MessageType.livenessPing.rawValue),
        "session_id": .bytes(Self.sampleSession),
        "sequence": .unsigned(0),
        "body": .map([
          "challenge": .bytes(Self.sampleDigest),
          "last_received_sequence": .unsigned(0),
        ]),
      ])
      let encoded = try envelope.encoded()
      let failure = CorpusFailure.name { _ = try Envelope.decode(encoded) }
      let outcome =
        switch failure {
        case nil:
          "accepted"

        case "UnsupportedVersion":
          "unsupported_version"

        case .some(let value):
          value
        }
      #expect(outcome == vector.expected, "\(vector.name)")
    }
  }

  @Test("Each direction advances by exactly one, bound to its own session")
  internal func sequenceGuard() throws {
    for vector in try CorpusFile.conformance(filePath: #filePath).sequenceGuard {
      let session = try Data(hex: vector.guardSessionIDHex)
      var sequenceGuard = SequenceGuard(sessionIdentifier: session)
      for sequence in vector.acceptedSequences {
        try sequenceGuard.acceptIncoming(sessionIdentifier: session, sequence: sequence)
      }

      let incomingSession = try Data(hex: vector.incomingSessionIDHex)
      let failure = CorpusFailure.name {
        try sequenceGuard.acceptIncoming(
          sessionIdentifier: incomingSession, sequence: vector.incomingSequence)
      }
      let outcome =
        switch failure {
        case nil:
          "accepted"

        case "WrongSession":
          "wrong_session"

        case .some(let value) where value.hasPrefix("WrongSequence"):
          "wrong_sequence"

        case .some(let value):
          value
        }
      #expect(outcome == vector.expected, "\(vector.name)")
      #expect(sequenceGuard.expectedNextReceive == vector.expectedNextReceive, "\(vector.name)")
    }
  }

  @Test("A profile may be exercised only if the pairing granted it")
  internal func grantEnforcement() throws {
    for vector in try CorpusFile.conformance(filePath: #filePath).grantEnforcement {
      let outcome =
        RappHashes.isGranted(profile: vector.requestedProfile, granted: vector.grantedProfiles)
        ? "accepted" : "profile_not_granted"
      #expect(outcome == vector.expected, "\(vector.name)")
    }
  }

  @Test("The grant set hashes the same however the peer ordered it")
  internal func grantsHash() throws {
    for vector in try CorpusFile.conformance(filePath: #filePath).grantsHash {
      let sorted = Array(Set(vector.profiles)).sorted { left, right in
        Array(left.utf8).lexicographicallyPrecedes(Array(right.utf8))
      }
      let canonical = try WireValue.array(sorted.map { .text($0) }).encoded()
      #expect(canonical.hex == vector.canonicalCBORHex, "\(vector.name)")
      #expect(try RappHashes.grantsHash(profiles: vector.profiles).hex == vector.sha256Hex)
    }
  }

  @Test("One typed request binds to exactly one session")
  internal func requestHash() throws {
    for vector in try CorpusFile.conformance(filePath: #filePath).requestHash {
      let binding = RappRequestBinding(
        sessionIdentifier: try Data(hex: vector.sessionIDHex),
        operationIdentifier: try Data(hex: vector.operationIDHex),
        profile: vector.profile,
        action: vector.action,
        context: try vector.context.mapValue("context"),
        payload: try vector.payload.mapValue("payload"))
      let preimage = try RappHashes.requestPreimage(of: binding)
      #expect(preimage.hex == vector.preimageCBORHex, "\(vector.name)")
      #expect(Data(SHA256.hash(data: preimage)).hex == vector.sha256Hex, "\(vector.name)")
    }
  }

  @Test("Identifiers are domain-separated halves of a transcript hash")
  internal func identifierDerivation() throws {
    for vector in try CorpusFile.conformance(filePath: #filePath).identifierDerivation {
      let hash = try Data(hex: vector.handshakeHashHex)
      #expect(RappNoise.pairIdentifier(handshakeHash: hash).hex == vector.pairIDHex)
      #expect(RappNoise.sessionIdentifier(handshakeHash: hash).hex == vector.sessionIDHex)
      #expect(RappNoise.rendezvousToken(handshakeHash: hash).hex == vector.rendezvousTokenHex)
    }
  }

  @Test("The plaintext preamble admits exactly the registered purposes")
  internal func streamRendezvous() throws {
    for vector in try CorpusFile.conformance(filePath: #filePath).streamRendezvous {
      let encoded = try Data(hex: vector.encodedHex)
      guard vector.accepted else {
        #expect(CorpusFailure.name { _ = try StreamRendezvous.decode(encoded) } == vector.error)
        continue
      }
      let rendezvous = try StreamRendezvous.decode(encoded)
      let expected: StreamRendezvous =
        vector.purpose == "session"
        ? .session(token: try Data(hex: vector.rendezvousTokenHex ?? "")) : .pairing
      #expect(rendezvous == expected, "\(vector.name)")
      #expect(try rendezvous.encoded().hex == vector.encodedHex, "\(vector.name)")
    }
  }

  @Test("A map whose keys arrive out of order is refused")
  internal func misorderedMapIsRefused() throws {
    // A two-entry map encoding the key "aa" before "z". Canonical order is by
    // encoded key, shorter first, so "z" must come first and these bytes are
    // not canonical however well formed they look.
    let misordered = try Data(hex: "a262616102617a01")
    #expect(CorpusFailure.name { _ = try decodeDeterministicCbor(misordered) } == "NonCanonical")
  }

  @Test("A well-formed envelope is accepted")
  internal func wellFormedEnvelopeIsAccepted() throws {
    let envelope = Envelope(
      messageType: .livenessPing, sessionIdentifier: Self.sampleSession, sequence: 0,
      body: [
        "challenge": .bytes(Self.sampleDigest), "last_received_sequence": .unsigned(0),
      ], critical: [], extensions: [:])
    let decoded = try Envelope.decode(try envelope.encoded())
    #expect(decoded == envelope)
  }
}
