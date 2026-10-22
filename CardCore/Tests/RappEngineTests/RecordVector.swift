// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored routing corpus (RAPP v26.10.22 §2.2.1 and §4.3).

internal struct RecordVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case expected = "expected"
    case hintsHex = "hints_hex"
    case instanceName = "instance_name"
    case name = "name"
    case requesterCounter = "requester_counter"
    case txt = "txt"
  }

  internal let name: String
  internal let txt: [[String]]
  internal let hintsHex: [String]
  internal let expected: String?
  internal let instanceName: String?
  internal let requesterCounter: UInt64?

  internal var entries: [(String, String)] {
    txt.map { ($0[0], $0[1]) }
  }

  internal init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    txt = try container.decode([[String]].self, forKey: .txt)
    hintsHex = try container.decodeIfPresent([String].self, forKey: .hintsHex) ?? []
    expected = try container.decodeIfPresent(String.self, forKey: .expected)
    instanceName = try container.decodeIfPresent(String.self, forKey: .instanceName)
    requesterCounter = try container.decodeIfPresent(UInt64.self, forKey: .requesterCounter)
  }

}
