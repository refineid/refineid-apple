// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// An RSA-3072 signature through a channel PACE opened with a PIN, against
/// a card that answers secure messaging itself.
///
/// The organization card on a reader's antenna answers the inline-digest
/// PSO:CDS with the whole protected signature in one response: DO'87'
/// around 384 bytes of signature, DO'99' and DO'8E', some 420 bytes, which
/// no short-form response carries. The command asks for it with the
/// short-form maximum, `Le = 00` outside and DO'97' `00` inside -- the
/// shape refineid-core sends and the card signs (observed on hardware).
@Suite
internal struct OrganizationProtectedSignatureTests {
  /// An arbitrary AES-256 Kenc for these exchanges.
  private static let encryptionKeyHex = String(repeating: "1F", count: 32)

  /// An arbitrary AES-256 Kmac, distinct from Kenc.
  private static let macKeyHex = String(repeating: "2E", count: 32)

  /// Normal processing.
  private static let successHex = "9000"

  /// The RSA-3072 signature width in bytes.
  private static let rsa3072SignatureLength = 384

  /// A T=1 response frame's room, larger than any protected RSA-3072
  /// answer.
  private static let readerFrameBudget = 1_024

  /// The repeated octet of the synthetic digest.
  private static let digestOctet: UInt8 = 0xAB

  @Test
  internal func aPin1ChannelCarriesAnRsa3072SignatureInOneResponse() throws {
    let signature = Data(
      (0..<Self.rsa3072SignatureLength).map { UInt8(truncatingIfNeeded: $0) })
    let digest = Data(repeating: Self.digestOctet, count: SigningHash.sha256.digestByteCount)
    let card = SecureMessagingMirrorCard(
      encryptionKey: WireHex.data(Self.encryptionKeyHex),
      macKey: WireHex.data(Self.macKeyHex),
      responses: [
        (Data(), WireHex.data(Self.successHex)),
        (signature, WireHex.data(Self.successHex)),
      ],
      fault: .honest,
      responseBudget: Self.readerFrameBudget
    )
    let keys = try #require(
      PaceSessionKeys(
        encryptionKey: WireHex.data(Self.encryptionKeyHex),
        macKey: WireHex.data(Self.macKeyHex)
      ))
    let operations = CardOperations(
      channel: SecureMessagingChannel(wrapping: card, sessionKeys: keys),
      openedWith: .pin1
    )

    let raw = try operations.computeAuthenticationSignature(
      overDigest: digest,
      algorithm: SigningAlgorithm(hash: .sha256, scheme: .rsaPss),
      expectedSignatureLength: nil
    )

    #expect(raw == signature)
    #expect(card.receivedCommands.count == 2)
    #expect(card.recoveredCommandData.last == digest)
    #expect(card.receivedExpectedLengths.last == 0)
    #expect(card.receivedCommands.last?.last == 0)
  }
}
