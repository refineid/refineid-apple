// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A `CardChannel` decorator that carries every APDU inside the ISO 7816-4
/// secure-messaging envelope PACE established.
///
/// This decorator is constructed ONLY on the contactless branch. PACE is the
/// contactless door and these keys are what it yields; the contact path
/// transmits plain APDUs on the bare transport and never sees this type. No
/// layer above can tell the two apart, because the decorator hands back
/// UNWRAPPED INNER bytes -- the plaintext body followed by the status word
/// that travelled in DO'99' -- so `CardOperations`, `BinaryReadAssembler`
/// and everything above them are unchanged by the transport choice.
///
/// A command's data is protected as DO'85' for an odd instruction byte or
/// DO'87' for an even instruction byte (the ISO 7816-4 padded plaintext under
/// AES-256-CBC, with the send-sequence counter encrypted under Kenc as the
/// IV), followed by DO'97' (the enclosed command's Le) and DO'8E' (the leading
/// eight bytes of an AES-CMAC over the padded concatenation of the counter,
/// the padded header and enclosed data objects). The class byte gets the
/// secure-messaging bits before the header is MACed, which is what binds
/// the header to the cryptogram.
///
/// The channel owns the send-sequence counter and pre-increments it in BOTH
/// directions, so a command uses counter `n` and its response `n + 1`, in
/// lockstep with the card.
///
/// Provenance: lifted from the RefineID iOS browser donor
/// `Sources/RefineIDBrowserKit/Card/SecureMessaging.swift` and the
/// `SecureCardSession` transmit of
/// `Sources/RefineIDBrowserKit/Card/CardSession.swift`.
public final class SecureMessagingChannel: CardChannel {
  /// Why a protected exchange was refused.
  public enum Failure: Error, Equatable {
    /// An earlier exchange on this channel failed, so the send-sequence
    /// counter may no longer match the card's; every later exchange is
    /// refused up front instead of failing its MAC unpredictably.
    case desynchronized

    /// The response's DO'8E' did not match the checksum computed over the
    /// received data objects. The channel is no longer trustworthy.
    case macMismatch

    /// The command handed in was not a short-form APDU this layer can
    /// take apart.
    case malformedCommand

    /// The response carried a secure-messaging body that was not the
    /// expected data objects.
    case malformedResponse

    /// The protected body would not fit a short-form command.
    case oversizedCommand
  }

  /// A parsed encrypted data object, preserving its tag because DO'85' and
  /// DO'87' have different value encodings and the tag is covered by the MAC.
  private struct CryptogramObject {
    let tag: UInt8
    let value: Data
  }

  /// The secure-messaging data objects of a response.
  private struct ResponseObjects {
    /// DO'85' or DO'87'; nil when the response carried no data.
    let cryptogram: CryptogramObject?

    /// DO'99', the two status bytes of the enclosed plain response.
    let status: Data

    /// DO'8E', the truncated checksum.
    let mac: Data
  }

  /// The four header bytes of any APDU.
  internal static let headerLength: Int = 4

  /// The largest body a short-form command APDU can carry.
  private static let maximumBodyLength: Int = 255
  internal static let evenInstructionRemainder: UInt8 = 2
  internal static let instructionByteIndex = 1

  /// Chunked reads over this channel ask for the secure-messaged chunk,
  /// never the plain one.
  ///
  /// Everything above this decorator is unchanged by the transport
  /// choice except for this one number, and it cannot be left out: a
  /// chunk whose DO'87' cryptogram, DO'99' and DO'8E' overran one
  /// short-form response would come back short on every read, and a read
  /// to end of file would take the first short chunk for the end of the
  /// file and return a truncated certificate with no error at all.
  public var readChunkLength: ReadChunkLength {
    .secureMessaged
  }

  /// The transport underneath, which sees only protected APDUs.
  private let plainChannel: any CardChannel

  /// Kenc, the encryption key.
  private let encryptionKey: Data

  /// Kmac, the authentication key.
  private let macKey: Data

  /// The send-sequence counter, pre-incremented in both directions.
  private var sendSequenceCounter: Data

  /// Set once a protected exchange has thrown: from then on the counter
  /// cannot be trusted to match the card's, and the channel fail-stops.
  private var failed = false

  /// Wraps `channel` in the session `sessionKeys` describes.
  ///
  /// Constructed only on the contactless branch, immediately after a
  /// successful PACE run and before any other command is sent: the counter
  /// starts at zero and the card's does too, so nothing may pass through
  /// the plain channel once this exists.
  public init(wrapping channel: any CardChannel, sessionKeys: PaceSessionKeys) {
    self.plainChannel = channel
    self.encryptionKey = sessionKeys.encryptionKey
    self.macKey = sessionKeys.macKey
    self.sendSequenceCounter = sessionKeys.initialSendSequenceCounter
  }

  /// The secure-messaging data objects carried by a response body.
  ///
  /// DO'99' and DO'8E' are both mandatory: the real status word never
  /// travels in the clear, so a response without a verified DO'99' has no
  /// status at all.
  private static func responseObjects(in body: Data) throws -> ResponseObjects {
    guard let records = try? DerTlvRecord.sequence(in: body) else {
      throw Failure.malformedResponse
    }
    var cryptogram: CryptogramObject?
    var status: Data?
    var mac: Data?
    for record in records {
      switch record.tag {
      case PaceValues.oddInstructionCryptogramTag, PaceValues.cryptogramTag:
        guard cryptogram == nil else { throw Failure.malformedResponse }
        cryptogram = CryptogramObject(tag: record.tag, value: record.value)

      case PaceValues.statusTag:
        status = record.value

      case PaceValues.macTag:
        mac = record.value

      default:
        continue
      }
    }
    guard
      let status, status.count == ResponseApdu.statusWordLength,
      let mac, mac.count == PaceValues.macLength
    else {
      throw Failure.malformedResponse
    }
    return ResponseObjects(cryptogram: cryptogram, status: status, mac: mac)
  }

  /// Protects one plain command, transmits it, and returns the unwrapped
  /// inner response as `payload || SW1 SW2`.
  ///
  /// The outer response is assembled across `61xx` continuations first,
  /// because the envelope's overhead pushes it past what a single
  /// short-form response can carry.
  ///
  /// Then the critical rule, carried from the donor: unwrap whenever there
  /// is a secure-messaging body, EVEN IF the outer status word is an error.
  /// A card answering READ BINARY at end of file returns `6282` at the
  /// outer level while still protecting the response, DO'8E' included --
  /// and it has already incremented its own send-sequence counter to
  /// produce that checksum. Returning early on the outer error would leave
  /// this side one behind forever, and every later APDU would fail its MAC
  /// for no visible reason. Only a response with no body at all -- a bare
  /// transport-level failure the card never protected -- is passed through
  /// untouched.
  public func transmit(_ payload: Data) throws -> Data {
    guard !failed else { throw Failure.desynchronized }
    do {
      let outer = try ContinuedResponse.transmitting(
        try wrap(payload),
        over: plainChannel
      )
      guard !outer.payload.isEmpty else { return outer.encoded }
      let unwrapped = try unwrap(outer.payload)
      var response = unwrapped.payload
      response.append(unwrapped.status)
      return response
    } catch Failure.malformedCommand {
      // Refused before the counter advanced and before any byte reached
      // the card: the channel is untouched and stays usable.
      throw Failure.malformedCommand
    } catch {
      failed = true
      throw error
    }
  }

  /// DO'85' or DO'87' for a command data field.
  ///
  /// DO'85' carries ciphertext directly for odd instructions; DO'87'
  /// prefixes it with the padding indicator for even instructions. An
  /// empty data field emits no object.
  private func cryptogramObject(
    for data: Data,
    hasOddInstruction: Bool
  ) throws -> Data {
    guard !data.isEmpty else { return Data() }
    var value =
      hasOddInstruction
      ? Data()
      : Data([PaceValues.paddingContentIndicator])
    value.append(
      try AesCbc.encrypt(
        key: encryptionKey,
        initializationVector: try currentInitializationVector(),
        plaintext: Self.padded(data)
      )
    )
    let tag =
      hasOddInstruction
      ? PaceValues.oddInstructionCryptogramTag
      : PaceValues.cryptogramTag
    guard let object = DerTlvRecord.encoded(tag: tag, value: value)
    else {
      throw Failure.oversizedCommand
    }
    return object
  }

  /// Builds the protected form of a plain command.
  private func wrap(_ plain: Data) throws -> Data {
    let parts = try Self.commandParts(of: plain)
    incrementSendSequenceCounter()
    let cryptogramObject = try cryptogramObject(
      for: parts.data,
      hasOddInstruction: parts.hasOddInstruction
    )
    let expectedLengthObject = try expectedLengthObject(for: parts.expectedLength)

    var macInput = sendSequenceCounter
    macInput.append(Self.padded(parts.header))
    macInput.append(cryptogramObject)
    macInput.append(expectedLengthObject)
    guard
      let macObject = DerTlvRecord.encoded(
        tag: PaceValues.macTag,
        value: try AesCmac.secureMessagingTag(
          key: macKey,
          message: Self.padded(macInput)
        )
      )
    else {
      throw Failure.oversizedCommand
    }

    let body = cryptogramObject + expectedLengthObject + macObject
    guard body.count <= Self.maximumBodyLength else {
      throw Failure.oversizedCommand
    }
    var wrapped = parts.header
    wrapped.append(UInt8(body.count))
    wrapped.append(body)
    wrapped.append(Iso7816Values.expectedLengthMaximumEncoding)
    return wrapped
  }

  /// Verifies and decrypts a protected response body.
  ///
  /// The checksum is recomputed over the counter and the data objects
  /// RE-ENCODED from their parsed values, never over a slice of the
  /// received bytes: verifying what was parsed is what makes the check
  /// meaningful.
  private func unwrap(_ body: Data) throws -> (payload: Data, status: Data) {
    incrementSendSequenceCounter()
    let objects = try Self.responseObjects(in: body)
    try verifyMac(objects)
    guard let cryptogram = objects.cryptogram else {
      return (Data(), objects.status)
    }
    return (try decryptCryptogram(cryptogram), objects.status)
  }

  /// Recomputes the response checksum over the counter and the data
  /// objects RE-ENCODED from their parsed values and refuses a mismatch.
  private func verifyMac(_ objects: ResponseObjects) throws {
    var macInput = sendSequenceCounter
    if let cryptogram = objects.cryptogram {
      guard
        let object = DerTlvRecord.encoded(
          tag: cryptogram.tag,
          value: cryptogram.value
        )
      else {
        throw Failure.malformedResponse
      }
      macInput.append(object)
    }
    guard
      let statusObject = DerTlvRecord.encoded(
        tag: PaceValues.statusTag,
        value: objects.status
      )
    else {
      throw Failure.malformedResponse
    }
    macInput.append(statusObject)
    let computed = try AesCmac.secureMessagingTag(
      key: macKey,
      message: Self.padded(macInput)
    )
    guard ConstantTimeComparison.equal(computed, objects.mac) else {
      throw Failure.macMismatch
    }
  }

  /// Strips the padding indicator and decrypts one response cryptogram.
  private func decryptCryptogram(_ cryptogram: CryptogramObject) throws -> Data {
    let ciphertext: Data
    switch cryptogram.tag {
    case PaceValues.oddInstructionCryptogramTag:
      ciphertext = cryptogram.value

    case PaceValues.cryptogramTag:
      guard cryptogram.value.first == PaceValues.paddingContentIndicator else {
        throw Failure.malformedResponse
      }
      ciphertext = Data(cryptogram.value.dropFirst())

    default:
      throw Failure.malformedResponse
    }
    guard !ciphertext.isEmpty, ciphertext.count.isMultiple(of: AesCbc.blockSize) else {
      throw Failure.malformedResponse
    }
    let plaintext = try AesCbc.decrypt(
      key: encryptionKey,
      initializationVector: try currentInitializationVector(),
      ciphertext: ciphertext
    )
    return Self.unpadded(plaintext)
  }

  /// The CBC initialization vector for the current counter value: the
  /// counter encrypted under Kenc with the raw block cipher
  /// (ICAO 9303-11 section 9.8.7).
  private func currentInitializationVector() throws -> Data {
    try AesCbc.encryptBlock(key: encryptionKey, block: sendSequenceCounter)
  }

  /// Adds one to the counter, big-endian, wrapping from the last byte.
  private func incrementSendSequenceCounter() {
    var index = sendSequenceCounter.count - 1
    while index >= 0, sendSequenceCounter[index] == UInt8.max {
      sendSequenceCounter[index] = 0
      index -= 1
    }
    guard index >= 0 else { return }
    sendSequenceCounter[index] += 1
  }
}
