// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

@Suite("RAPP v26.11.2 display names on pairing and on every session (sections 4.3 and 7.1)")
internal struct DisplayNameVectorTests {
  private static let sessionReady = "session.ready"

  private func corpus(_ filePath: String = #filePath) throws -> DisplayNameCorpus {
    try CorpusFile.displayNames(filePath: filePath)
  }

  /// The envelope and its typed body re-encoded, or nil when the name
  /// refuses it.
  private func parsed(_ vector: DisplayNameVector) throws -> Envelope? {
    guard let envelope = try? Envelope.decode(try Data(hex: vector.envelopeHex)) else {
      return nil
    }
    switch envelope.messageType {
    case .pairingHello:
      guard let hello = try? PairingHello.from(body: envelope.body) else { return nil }
      return reencoded(envelope, body: try hello.body())

    case .sessionReady:
      guard let ready = try? SessionReady.from(body: envelope.body) else { return nil }
      return reencoded(envelope, body: try ready.body())

    case .sessionHello:
      guard let hello = try? SessionHello.from(body: envelope.body) else { return nil }
      return reencoded(envelope, body: hello.body())

    default:
      return nil
    }
  }

  /// `envelope` with its body built again from the typed message.
  private func reencoded(_ envelope: Envelope, body: [String: WireValue]) -> Envelope {
    Envelope(
      messageType: envelope.messageType, sessionIdentifier: envelope.sessionIdentifier,
      sequence: envelope.sequence, body: body)
  }

  @Test("Every pairing.hello name is accepted or refused as the vector says, byte for byte")
  internal func pairingHelloNames() throws {
    let vectors = try corpus().pairingHello
    #expect(!vectors.isEmpty)
    for vector in vectors {
      let accepted = vector.expected == DisplayNameVector.accepted
      let result = try parsed(vector)
      #expect((result != nil) == accepted, "\(vector.name)")
      guard let envelope = result else { continue }
      let hello = try PairingHello.from(body: envelope.body)
      #expect(hello.displayName.text == vector.displayName, "\(vector.name)")
      #expect(try envelope.encoded().hex == vector.envelopeHex, "\(vector.name) encodes back")
    }
  }

  @Test("Every session name is checked, re-encoded and recorded as the vector says")
  internal func sessionNames() throws {
    let vectors = try corpus().sessionName
    #expect(!vectors.isEmpty)
    for vector in vectors {
      let accepted = vector.expected == DisplayNameVector.accepted
      let result = try parsed(vector)
      #expect((result != nil) == accepted, "\(vector.name)")
      let before = try #require(vector.recordNameBefore.flatMap { RappDisplayName($0) })
      let record = try makePairRecord().renamed(before)
      guard let envelope = result else {
        #expect(record.peerDisplayName == vector.recordNameAfter, "\(vector.name) keeps its name")
        continue
      }
      #expect(try envelope.encoded().hex == vector.envelopeHex, "\(vector.name) encodes back")
      let name =
        vector.message == Self.sessionReady
        ? try SessionReady.from(body: envelope.body).displayName
        : try SessionHello.from(body: envelope.body).displayName
      let renamed = record.peerDisplayName == name.text ? record : record.renamed(name)
      #expect(renamed.peerDisplayName == vector.recordNameAfter, "\(vector.name)")
      #expect((renamed != record) == vector.recordRewritten, "\(vector.name) rewrites")
    }
  }

  @Test("A sender shortens its name at a character boundary to fit the bound")
  internal func shortening() throws {
    let twoByteCharacter = "\u{f6}"
    let overBound =
      String(
        repeating: twoByteCharacter,
        count: RappDisplayName.maximumBytes / twoByteCharacter.utf8.count)
      + twoByteCharacter
    let shortened = try #require(RappDisplayName(shortening: overBound))
    #expect(shortened.text.utf8.count == RappDisplayName.maximumBytes)
    #expect(RappDisplayName(overBound) == nil)
    #expect(RappDisplayName(shortening: " \t ") == nil)
  }
}
