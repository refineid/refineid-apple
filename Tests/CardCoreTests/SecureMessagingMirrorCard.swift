// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// A synthetic contactless card that plays the card half of ISO 7816-4
/// secure messaging, with its own independently maintained send-sequence
/// counter.
///
/// This is the counterpart the channel is actually specified against. A
/// scripted byte comparison would only prove the wrapper reproduces bytes
/// somebody once wrote down; a card that computes the same MACs from the
/// same rules proves the two sides agree - and, crucially, that they stay
/// agreed, because this card increments its counter on both directions too.
/// If the channel ever skipped an increment, the very next command would
/// fail this card's MAC check.
internal final class SecureMessagingMirrorCard: CardChannel {
  /// Whether the card protects its response correctly.
  internal enum Fault {
    /// Answer honestly.
    case honest

    /// Corrupt DO'8E' so the terminal must reject the response.
    case tamperedMac
  }

  /// Thrown when the terminal's command does not verify, or the script is
  /// exhausted.
  internal struct Rejected: Error, Equatable {}

  /// Secure-messaging DO'87', the cryptogram.
  private static let cryptogramTag: UInt8 = 0x87

  /// Secure-messaging DO'97', the enclosed Le.
  private static let expectedLengthTag: UInt8 = 0x97

  /// Secure-messaging DO'99', the enclosed status word.
  private static let statusTag: UInt8 = 0x99

  /// Secure-messaging DO'8E', the checksum.
  private static let macTag: UInt8 = 0x8E

  /// The DO'87' padding-content indicator for ISO 7816-4 padding method 2.
  private static let paddingContentIndicator: UInt8 = 0x01

  /// The ISO 7816-4 padding method 2 marker.
  private static let paddingMarker: UInt8 = 0x80

  /// The four header bytes of any APDU.
  private static let headerLength: Int = 4

  /// Where a short-form command's body starts.
  private static let bodyOffset: Int = 5

  /// The mask that flips every bit of the byte it is applied to.
  private static let flipEveryBit: UInt8 = 0xFF

  /// All the room the card has for one protected response: a short-form
  /// response, status word included.
  ///
  /// A card cannot answer more than this however much the terminal asks
  /// for, and DO'87' spends part of it on padding, a tag and length
  /// octets before DO'99' and DO'8E' take their share. Modelling that
  /// here is what makes a chunked read against this card a real test:
  /// ask for more plaintext than the envelope carries and the answer
  /// comes back short, exactly as it would on hardware.
  private static let outerBudget: Int = ExpectedResponseLength.maximum

  /// Kenc.
  private let encryptionKey: Data

  /// Kmac.
  private let macKey: Data

  /// Whether responses are protected honestly.
  private let fault: Fault

  /// The bytes one response may carry, status word included.
  private let responseBudget: Int

  /// The remaining scripted inner responses, as plaintext and status word.
  private var scripted: [(payload: Data, statusWord: Data)]

  /// The card's own send-sequence counter.
  private var sendSequenceCounter: Data

  /// This card is the wire under `SecureMessagingChannel`, not a read
  /// transport of its own: it hands back the outer bytes unchanged, so
  /// the plain chunk is what it would carry.
  internal var readChunkLength: ReadChunkLength {
    .plain
  }

  /// The plain command data field recovered from each command, in order.
  internal private(set) var recoveredCommandData: [Data] = []

  /// The complete protected command received from the terminal.
  ///
  /// Retained so integration tests can hand the wrapper's actual output to
  /// transport-specific framing decisions instead of reconstructing a
  /// synthetic secure-messaging envelope.
  internal private(set) var receivedCommands: [Data] = []

  /// The protected header received with each command, in order.
  internal private(set) var receivedHeaders: [Data] = []

  /// The enclosed command's Le from DO'97', one entry per command in
  /// order, nil when the command asked for no response data.
  ///
  /// Recorded so a test can state the exact sequence of lengths the
  /// terminal asked this card for, which is the wire fact a chunked read
  /// over secure messaging turns on.
  internal private(set) var receivedExpectedLengths: [UInt8?] = []

  /// The counter value the card used to verify each command, in order.
  ///
  /// Recorded so a test can state the expected sequence directly rather
  /// than inferring it from the fact that nothing failed.
  internal private(set) var commandCounters: [Data] = []

  internal convenience init(
    encryptionKey: Data,
    macKey: Data,
    responses: [(payload: Data, statusWord: Data)],
    fault: Fault
  ) {
    self.init(
      encryptionKey: encryptionKey,
      macKey: macKey,
      responses: responses,
      fault: fault,
      responseBudget: Self.outerBudget
    )
  }

  /// A card whose one response may carry `responseBudget` bytes, status
  /// word included: a reader's T=1 frame carries a whole protected RSA-3072
  /// signature, which no short-form response can.
  internal init(
    encryptionKey: Data,
    macKey: Data,
    responses: [(payload: Data, statusWord: Data)],
    fault: Fault,
    responseBudget: Int
  ) {
    self.encryptionKey = encryptionKey
    self.macKey = macKey
    self.fault = fault
    self.scripted = responses
    self.responseBudget = responseBudget
    self.sendSequenceCounter = Data(repeating: 0, count: AesCbc.blockSize)
  }

  /// ISO 7816-4 padding method 2, written independently of the channel's.
  private static func padded(_ data: Data) -> Data {
    var buffer = data
    buffer.append(Self.paddingMarker)
    let remainder = buffer.count % AesCbc.blockSize
    if remainder != 0 {
      buffer.append(contentsOf: repeatElement(0, count: AesCbc.blockSize - remainder))
    }
    return buffer
  }

  /// Strips ISO 7816-4 padding method 2.
  private static func unpadded(_ data: Data) -> Data {
    let bytes = Array(data)
    var end = bytes.count
    while end > 0, bytes[end - 1] == 0 {
      end -= 1
    }
    guard end > 0, bytes[end - 1] == Self.paddingMarker else { return data }
    return Data(bytes[0..<(end - 1)])
  }

  /// One data object, refusing anything the encoder cannot represent.
  private static func object(tag: UInt8, value: Data) throws -> Data {
    guard let encoded = DerTlvRecord.encoded(tag: tag, value: value) else {
      throw Rejected()
    }
    return encoded
  }

  /// Verifies and decrypts one protected command, then answers the next
  /// scripted response, protected in turn.
  internal func transmit(_ payload: Data) throws -> Data {
    receivedCommands.append(payload)
    let recovered = try accept(payload)
    recoveredCommandData.append(recovered)
    guard !scripted.isEmpty else { throw Rejected() }
    return try answer(scripted.removeFirst())
  }

  /// Checks the terminal's command and returns its plain data field.
  private func accept(_ payload: Data) throws -> Data {
    let bytes = Array(payload)
    guard bytes.count > Self.bodyOffset else { throw Rejected() }
    let header = Data(bytes.prefix(Self.headerLength))
    receivedHeaders.append(header)
    let bodyLength = Int(bytes[Self.headerLength])
    guard bytes.count >= Self.bodyOffset + bodyLength else { throw Rejected() }
    let body = Data(bytes[Self.bodyOffset..<(Self.bodyOffset + bodyLength)])

    increment()
    commandCounters.append(sendSequenceCounter)

    var cryptogram: Data?
    var macInput = sendSequenceCounter + Self.padded(header)
    var received: Data?
    var enclosedExpectedLength: UInt8?
    for record in try DerTlvRecord.sequence(in: body) {
      switch record.tag {
      case Self.cryptogramTag:
        cryptogram = record.value
        macInput += try Self.object(tag: record.tag, value: record.value)

      case Self.expectedLengthTag:
        enclosedExpectedLength = record.value.first
        macInput += try Self.object(tag: record.tag, value: record.value)

      case Self.macTag:
        received = record.value

      default:
        throw Rejected()
      }
    }
    receivedExpectedLengths.append(enclosedExpectedLength)
    let computed = try AesCmac.secureMessagingTag(key: macKey, message: Self.padded(macInput))
    guard computed == received else { throw Rejected() }
    guard let cryptogram else { return Data() }
    guard cryptogram.first == Self.paddingContentIndicator else { throw Rejected() }
    return Self.unpadded(
      try AesCbc.decrypt(
        key: encryptionKey,
        initializationVector: try initializationVector(),
        ciphertext: Data(cryptogram.dropFirst())
      )
    )
  }

  /// Protects one scripted response, trimmed to what the card can
  /// actually send back.
  ///
  /// The status word is placed both inside DO'99' and at the outer level,
  /// which is what a real card does: an error such as end of file shows up
  /// outside while the response body stays protected.
  ///
  /// The trimming loop drops one plaintext byte at a time and protects
  /// the shorter body again rather than predicting the envelope's size
  /// from a formula: the card is specified against the same rules the
  /// terminal is, so the only honest measure of what fits is a protected
  /// body that was actually built.
  private func answer(_ response: (payload: Data, statusWord: Data)) throws -> Data {
    increment()
    var payload = response.payload
    var body = try protectedBody(payload: payload, statusWord: response.statusWord)
    while !payload.isEmpty,
      body.count + ResponseApdu.statusWordLength > responseBudget
    {
      payload = Data(payload.dropLast())
      body = try protectedBody(payload: payload, statusWord: response.statusWord)
    }
    return body + response.statusWord
  }

  /// One protected response body: DO'87' when there is plaintext, then
  /// DO'99' and DO'8E'.
  private func protectedBody(payload: Data, statusWord: Data) throws -> Data {
    var body = Data()
    if !payload.isEmpty {
      var value = Data([Self.paddingContentIndicator])
      value += try AesCbc.encrypt(
        key: encryptionKey,
        initializationVector: try initializationVector(),
        plaintext: Self.padded(payload)
      )
      body += try Self.object(tag: Self.cryptogramTag, value: value)
    }
    body += try Self.object(tag: Self.statusTag, value: statusWord)
    var tag = try AesCmac.secureMessagingTag(
      key: macKey,
      message: Self.padded(sendSequenceCounter + body)
    )
    if fault == .tamperedMac {
      tag[tag.startIndex] ^= Self.flipEveryBit
    }
    body += try Self.object(tag: Self.macTag, value: tag)
    return body
  }

  /// The CBC initialization vector for the current counter.
  private func initializationVector() throws -> Data {
    try AesCbc.encryptBlock(key: encryptionKey, block: sendSequenceCounter)
  }

  /// Adds one to the counter, big-endian.
  private func increment() {
    var index = sendSequenceCounter.count - 1
    while index >= 0, sendSequenceCounter[index] == UInt8.max {
      sendSequenceCounter[index] = 0
      index -= 1
    }
    guard index >= 0 else { return }
    sendSequenceCounter[index] += 1
  }
}
