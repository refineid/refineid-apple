// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A package request built entry by entry until it no longer fits one
/// frame.
internal struct FrameBoundVector: Decodable {
  private enum CodingKeys: String, CodingKey {
    case name = "name"
    case documentName = "document_name"
    case entryBytes = "entry_bytes"
    case entryIndexDigits = "entry_index_digits"
    case smallestRefusedCount = "smallest_refused_count"
    case admittedEnvelopeLength = "admitted_envelope_length"
    case refusedEnvelopeLength = "refused_envelope_length"
  }

  internal let name: String
  internal let documentName: String
  internal let entryBytes: Int
  internal let entryIndexDigits: Int
  internal let smallestRefusedCount: Int
  internal let admittedEnvelopeLength: Int
  internal let refusedEnvelopeLength: Int

  /// Entry `index`: its zero-padded decimal index padded with the letter x
  /// to ``entryBytes`` bytes.
  internal func entry(_ index: Int) -> String {
    let digits = String(index)
    let padded = String(repeating: "0", count: max(0, entryIndexDigits - digits.count)) + digits
    return padded + String(repeating: "x", count: entryBytes - padded.utf8.count)
  }
}
