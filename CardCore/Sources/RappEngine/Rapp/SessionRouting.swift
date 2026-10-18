// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// `nonce || routing_tag` of a session preamble (RAPP v26.10.18 §2.2.1).
internal struct SessionRouting: Equatable {
  internal static let nonceSize = 16
  internal static let tagSize = 16
  internal static let size = nonceSize + tagSize

  internal let nonce: Data
  internal let tag: Data

  internal var bytes: Data { nonce + tag }

  internal init(nonce: Data, tag: Data) {
    self.nonce = nonce
    self.tag = tag
  }

  internal init?(_ bytes: Data) {
    guard bytes.count == Self.size else { return nil }
    nonce = Data(bytes.prefix(Self.nonceSize))
    tag = Data(bytes.suffix(Self.tagSize))
  }
}
