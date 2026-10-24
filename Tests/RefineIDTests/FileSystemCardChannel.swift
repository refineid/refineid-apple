// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import CardCore

/// A card that answers SELECT and READ BINARY from a map of elementary
/// files, and success to every other command, recording which files are
/// read and how many commands arrive.
internal final class FileSystemCardChannel: CardChannel, @unchecked Sendable {
  /// Offset of the instruction byte in a command.
  private static let instructionOffset = 1

  /// Offset of P1 in a command.
  private static let parameter1Offset = 2

  /// Offset of P2 in a command.
  private static let parameter2Offset = 3

  /// Offset of the command data in a short command.
  private static let dataOffset = 5

  /// Length of a short command header with its Lc or Le byte.
  private static let headerWithLength = 5

  /// Bytes in a file identifier.
  private static let fileIdentifierLength = 2

  /// The expected length an Le byte of zero stands for.
  private static let maximumShortExpectedLength = 256

  private let files: [UInt16: Data]
  private var current: UInt16?

  /// The elementary files read, in order, one entry per read from offset
  /// zero.
  internal private(set) var filesRead: [UInt16] = []

  /// Every command the card received.
  internal private(set) var commandCount = 0

  internal var readChunkLength: ReadChunkLength {
    .plain
  }

  /// A card holding each file's content under its identifier.
  internal init(files: [(FileIdentifier, Data)]) {
    self.files = Dictionary(uniqueKeysWithValues: files.map { ($0.0.value, $0.1) })
  }

  private static func status(_ word: StatusWord) -> Data {
    Data([
      UInt8(word.encoded >> UInt16(Iso7816Values.byteShift)),
      UInt8(word.encoded & Iso7816Values.lowByteMask),
    ])
  }

  internal func transmit(_ payload: Data) -> Data {
    commandCount += 1
    let bytes = [UInt8](payload)
    switch bytes[Self.instructionOffset] {
    case Iso7816Values.insSelect:
      return Self.status(select(bytes))

    case Iso7816Values.insReadBinary:
      return readBinary(bytes)

    default:
      return Self.status(.success)
    }
  }

  private func select(_ bytes: [UInt8]) -> StatusWord {
    guard bytes[Self.parameter1Offset] != Iso7816Values.selectByAidP1 else {
      current = nil
      return .success
    }
    let identifier = bytes[Self.dataOffset..<(Self.dataOffset + Self.fileIdentifierLength)]
      .reduce(UInt16(0)) { ($0 << Iso7816Values.byteShift) | UInt16($1) }
    if identifier == FileIdentifier.mainFile.value {
      current = nil
      return .success
    }
    guard files[identifier] != nil else { return .fileNotFound }
    current = identifier
    return .success
  }

  private func readBinary(_ bytes: [UInt8]) -> Data {
    guard let current, let content = files[current] else {
      return Self.status(.fileNotFound)
    }
    let offset =
      Int(bytes[Self.parameter1Offset]) << Iso7816Values.byteShift
      | Int(bytes[Self.parameter2Offset])
    if offset == 0 { filesRead.append(current) }
    let requested = bytes.count == Self.headerWithLength ? Int(bytes[bytes.count - 1]) : 0
    let length = requested == 0 ? Self.maximumShortExpectedLength : requested
    let start = min(offset, content.count)
    let end = min(start + length, content.count)
    return content.subdata(in: start..<end) + Self.status(.success)
  }
}
