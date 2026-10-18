// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A session record that may carry a revocation announcement.
internal struct RevokedSessionRecordVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case expected = "expected"
    case hintsHex = "hints_hex"
    case instanceName = "instance_name"
    case name = "name"
    case requesterEpoch = "requester_epoch"
    case txt = "txt"
  }

  internal let name: String
  internal let txt: [[String]]
  internal let hintsHex: [String]
  internal let expected: String?
  internal let instanceName: String?
  internal let requesterEpoch: UInt64?

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
    requesterEpoch = try container.decodeIfPresent(UInt64.self, forKey: .requesterEpoch)
  }
}
