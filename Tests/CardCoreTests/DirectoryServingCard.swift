// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// A citizen card serving `directory` as its EF.AOD.
///
/// It answers the numbering probe and selects the eID application; with
/// no directory the file is absent. Any credential-bearing command is
/// recorded as an issue: nothing here may send one.
internal final class DirectoryServingCard: CardChannel {
  /// A command this card does not serve.
  internal struct UnexpectedCommand: Error {}

  /// The retry count the numbering probe reports.
  private static let probedAttempts: UInt8 = 5

  private let directory: Data?
  private var served = false

  internal var readChunkLength: ReadChunkLength {
    .plain
  }

  internal init(directory: Data?) {
    self.directory = directory
  }

  private static func response(_ payload: Data, _ statusWord: StatusWord) -> Data {
    let word = statusWord.encoded
    return payload
      + Data([UInt8(word >> UInt8.bitWidth), UInt8(truncatingIfNeeded: word)])
  }

  internal func transmit(_ payload: Data) throws -> Data {
    switch payload {
    case CommandApdu.readRetryCounter(role: .pin1, references: .citizen).encoded:
      guard let remaining = RetryCount(attemptsRemaining: Self.probedAttempts) else {
        throw UnexpectedCommand()
      }
      return Self.response(Data(), .pinIncorrect(remaining: remaining))

    case CommandApdu.selectApplication(.fineidApplication).encoded:
      return Self.response(Data(), .success)

    case CommandApdu.selectElementaryFile(.authenticationObjectDirectory).encoded:
      return Self.response(Data(), directory == nil ? .fileNotFound : .success)

    default:
      guard let directory, payload.dropFirst().first == Iso7816Values.insReadBinary else {
        Issue.record("unexpected command")
        throw UnexpectedCommand()
      }
      defer { served = true }
      return served ? Self.response(Data(), .endOfFile) : Self.response(directory, .success)
    }
  }
}
