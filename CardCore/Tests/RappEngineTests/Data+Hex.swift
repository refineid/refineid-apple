// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RappEngine

extension Data {
  /// Number of hexadecimal characters per byte.
  private static let charactersPerByte = 2

  /// Bits a high nibble is shifted by.
  private static let nibbleBits: UInt8 = 4

  /// Value of the first hexadecimal letter.
  private static let firstLetterValue: UInt8 = 10

  internal var hex: String {
    map { String(format: "%02x", $0) }.joined()
  }

  /// Corpus vectors are written as hex, so tests read them back the same way.
  internal init(hex: String) throws {
    let characters = Array(hex.utf8)
    guard characters.count.isMultiple(of: Self.charactersPerByte) else {
      throw CorpusError.invalidHex
    }
    self.init()
    reserveCapacity(characters.count / Self.charactersPerByte)
    for index in stride(from: 0, to: characters.count, by: Self.charactersPerByte) {
      guard
        let high = Self.hexNibble(characters[index]),
        let low = Self.hexNibble(characters[index + 1])
      else { throw CorpusError.invalidHex }
      append((high << Self.nibbleBits) | low)
    }
  }

  private static func hexNibble(_ byte: UInt8) -> UInt8? {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"):
      byte - UInt8(ascii: "0")

    case UInt8(ascii: "A")...UInt8(ascii: "F"):
      byte - UInt8(ascii: "A") + firstLetterValue

    case UInt8(ascii: "a")...UInt8(ascii: "f"):
      byte - UInt8(ascii: "a") + firstLetterValue

    default:
      nil
    }
  }
}

extension RappOperationIdentifier {
  /// The corpus writes identifiers as hex too.
  internal init(hex: String) throws {
    guard let identifier = Self(try Data(hex: hex)) else { throw CorpusError.invalidHex }
    self = identifier
  }
}
