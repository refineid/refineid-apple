// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The vendored routing corpus (RAPP v26.10.18 §2.2.1 and §4.3).

internal struct WithdrawnRecordVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case expected = "expected"
    case instanceName = "instance_name"
    case name = "name"
    case requesterCounter = "requester_counter"
    case txt = "txt"
  }

  internal let name: String
  internal let instanceName: String
  internal let requesterCounter: UInt64
  internal let txt: [[String]]
  internal let expected: String

  internal var entries: [(String, String)] {
    txt.map { ($0[0], $0[1]) }
  }
}
