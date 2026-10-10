// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension RappConformanceCorpusSupport {
  // MARK: Nested Types

  private enum CorpusKeys: String, CodingKey {
    case deterministicCBOR = "deterministic_cbor"
    case format = "format"
    case grantsHash = "grants_hash"
    case identifierDerivation = "identifier_derivation"
    case protocolDocumentVersion = "protocol_document_version"
    case rejectedCBOR = "rejected_cbor"
    case requestHash = "request_hash"
    case streamRendezvous = "stream_rendezvous"
  }

  private enum CBORVectorKeys: String, CodingKey {
    case encodedHex = "encoded_hex"
    case name = "name"
    case value = "value"
  }

  private enum IdentifierVectorKeys: String, CodingKey {
    case handshakeHashHex = "handshake_hash_hex"
    case name = "name"
    case pairIDHex = "pair_id_hex"
    case rendezvousTokenHex = "rendezvous_token_hex"
    case sessionIDHex = "session_id_hex"
  }

  private enum StreamRendezvousVectorKeys: String, CodingKey {
    case accepted = "accepted"
    case encodedHex = "encoded_hex"
    case error = "error"
    case name = "name"
    case purpose = "purpose"
    case rendezvousTokenHex = "rendezvous_token_hex"
  }

  private enum GrantsVectorKeys: String, CodingKey {
    case canonicalCBORHex = "canonical_cbor_hex"
    case name = "name"
    case profiles = "profiles"
    case sha256Hex = "sha256_hex"
  }

  private enum RequestVectorKeys: String, CodingKey {
    case action = "action"
    case context = "context"
    case name = "name"
    case operationIDHex = "operation_id_hex"
    case payload = "payload"
    case pairIDHex = "pair_id_hex"
    case preimageCBORHex = "preimage_cbor_hex"
    case profile = "profile"
    case sha256Hex = "sha256_hex"
  }

  private enum RejectedCBORVectorKeys: String, CodingKey {
    case encodedHex = "encoded_hex"
    case error = "error"
    case name = "name"
  }

  internal struct Corpus: Decodable {
    // MARK: Properties

    internal let format: String
    internal let protocolDocumentVersion: String
    internal let deterministicCBOR: [CBORVector]
    internal let identifierDerivation: [IdentifierVector]
    internal let grantsHash: [GrantsVector]
    internal let requestHash: [RequestVector]
    internal let rejectedCBOR: [RejectedCBORVector]
    internal let streamRendezvous: [StreamRendezvousVector]

    // MARK: Lifecycle

    internal init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CorpusKeys.self)
      format = try container.decode(String.self, forKey: .format)
      protocolDocumentVersion = try container.decode(String.self, forKey: .protocolDocumentVersion)
      deterministicCBOR = try container.decode([CBORVector].self, forKey: .deterministicCBOR)
      identifierDerivation = try container.decode(
        [IdentifierVector].self, forKey: .identifierDerivation)
      grantsHash = try container.decode([GrantsVector].self, forKey: .grantsHash)
      requestHash = try container.decode([RequestVector].self, forKey: .requestHash)
      rejectedCBOR = try container.decode([RejectedCBORVector].self, forKey: .rejectedCBOR)
      streamRendezvous = try container.decode(
        [StreamRendezvousVector].self, forKey: .streamRendezvous)
    }
  }

  internal struct CBORVector: Decodable {
    // MARK: Properties

    internal let name: String
    internal let value: CorpusValue
    internal let encodedHex: String

    // MARK: Lifecycle

    internal init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CBORVectorKeys.self)
      name = try container.decode(String.self, forKey: .name)
      value = try container.decode(CorpusValue.self, forKey: .value)
      encodedHex = try container.decode(String.self, forKey: .encodedHex)
    }
  }

  internal struct IdentifierVector: Decodable {
    // MARK: Properties

    internal let name: String
    internal let handshakeHashHex: String
    internal let pairIDHex: String
    internal let sessionIDHex: String
    internal let rendezvousTokenHex: String

    // MARK: Lifecycle

    internal init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: IdentifierVectorKeys.self)
      name = try container.decode(String.self, forKey: .name)
      handshakeHashHex = try container.decode(String.self, forKey: .handshakeHashHex)
      pairIDHex = try container.decode(String.self, forKey: .pairIDHex)
      sessionIDHex = try container.decode(String.self, forKey: .sessionIDHex)
      rendezvousTokenHex = try container.decode(String.self, forKey: .rendezvousTokenHex)
    }
  }

  internal struct StreamRendezvousVector: Decodable {
    // MARK: Properties

    internal let name: String
    internal let accepted: Bool
    internal let purpose: String
    internal let encodedHex: String
    internal let rendezvousTokenHex: String?
    internal let error: String?

    // MARK: Lifecycle

    internal init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: StreamRendezvousVectorKeys.self)
      name = try container.decode(String.self, forKey: .name)
      accepted = try container.decode(Bool.self, forKey: .accepted)
      purpose = try container.decode(String.self, forKey: .purpose)
      encodedHex = try container.decode(String.self, forKey: .encodedHex)
      rendezvousTokenHex = try container.decodeIfPresent(String.self, forKey: .rendezvousTokenHex)
      error = try container.decodeIfPresent(String.self, forKey: .error)
    }
  }

  internal struct GrantsVector: Decodable {
    // MARK: Properties

    internal let name: String
    internal let profiles: [String]
    internal let canonicalCBORHex: String
    internal let sha256Hex: String

    // MARK: Lifecycle

    internal init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: GrantsVectorKeys.self)
      name = try container.decode(String.self, forKey: .name)
      profiles = try container.decode([String].self, forKey: .profiles)
      canonicalCBORHex = try container.decode(String.self, forKey: .canonicalCBORHex)
      sha256Hex = try container.decode(String.self, forKey: .sha256Hex)
    }
  }

  internal struct RequestVector: Decodable {
    // MARK: Properties

    internal let name: String
    internal let pairIDHex: String
    internal let operationIDHex: String
    internal let profile: String
    internal let action: String
    internal let context: CorpusValue
    internal let payload: CorpusValue
    internal let preimageCBORHex: String
    internal let sha256Hex: String

    // MARK: Lifecycle

    internal init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: RequestVectorKeys.self)
      name = try container.decode(String.self, forKey: .name)
      pairIDHex = try container.decode(String.self, forKey: .pairIDHex)
      operationIDHex = try container.decode(String.self, forKey: .operationIDHex)
      profile = try container.decode(String.self, forKey: .profile)
      action = try container.decode(String.self, forKey: .action)
      context = try container.decode(CorpusValue.self, forKey: .context)
      payload = try container.decode(CorpusValue.self, forKey: .payload)
      preimageCBORHex = try container.decode(String.self, forKey: .preimageCBORHex)
      sha256Hex = try container.decode(String.self, forKey: .sha256Hex)
    }
  }

  internal struct RejectedCBORVector: Decodable {
    // MARK: Properties

    internal let name: String
    internal let encodedHex: String
    internal let error: String

    // MARK: Lifecycle

    internal init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: RejectedCBORVectorKeys.self)
      name = try container.decode(String.self, forKey: .name)
      encodedHex = try container.decode(String.self, forKey: .encodedHex)
      error = try container.decode(String.self, forKey: .error)
    }
  }
}
