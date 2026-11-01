// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// Holds the authentication token encoding to the shape the reference
/// implementation produces.
///
/// This is a conformance test, not a self-consistency one, and the
/// distinction is the point. `PaceEstablishmentTests` runs a synthetic
/// card that computes with this same implementation, so both sides agree
/// even when both are wrong. The expectations below come from the Rust
/// reference's own assertions on real hardware
/// (`crates/refineid-lib-core/src/pace.rs`), so a divergence here is a
/// divergence from what the card accepts.
///
/// `@testable` is used deliberately: the encoder is internal, and the
/// alternative -- widening it to public so a test can see it -- would
/// change the module's surface to suit a test rather than a caller.
///
/// The token matters more than its size suggests: it is the message
/// whose MAC proves to the card that we hold the same keys. Encode it
/// differently and the card sees a wrong authentication token, which is
/// indistinguishable to it from a wrong card access number -- and cards
/// answer a suspected wrong password by getting slower.
@Suite
internal struct PaceAuthenticationTokenTests {
  /// Tag bytes of the public-key data object, `7F49`.
  private static let dataObjectTag: [UInt8] = [0x7F, 0x49]

  /// Inner length the reference asserts: 111 bytes, short form.
  private static let innerLength: UInt8 = 0x6F

  /// DER tag for an object identifier.
  private static let oidTag: UInt8 = 0x06

  /// Length of the PACE mechanism OID body.
  private static let oidLength: UInt8 = 0x0A

  /// Context tag carrying the elliptic-curve point.
  private static let pointTag: UInt8 = 0x86

  /// Length of an uncompressed P-384 point: 97 bytes.
  private static let pointLength: UInt8 = 0x61

  /// SEC1 marker for an uncompressed point.
  private static let uncompressedMarker: UInt8 = 0x04

  /// Total encoded length: two tag bytes, one length byte, 111 inner.
  private static let totalLength: Int = 3 + 111

  @Test
  internal func tokenMatchesTheReferenceEncoding() throws {
    let token = try PaceDataObject.authenticationTokenInput(
      for: BrainpoolP384r1.generator,
      suite: PaceInfo(mapping: .generic, domain: .brainpoolP384r1)
    )
    let bytes = Array(token)

    #expect(bytes.count == Self.totalLength)
    #expect(Array(bytes[0..<2]) == Self.dataObjectTag)
    // Short form, not long form: 111 fits in one byte, and a card that
    // was handed 81 6F would MAC something else entirely.
    #expect(bytes[2] == Self.innerLength)
    #expect(bytes[3] == Self.oidTag)
    #expect(bytes[4] == Self.oidLength)
    #expect(bytes[15] == Self.pointTag)
    #expect(bytes[16] == Self.pointLength)
    #expect(bytes[17] == Self.uncompressedMarker)
  }

  @Test
  internal func theOidBodySitsWhereTheCardExpectsIt() throws {
    let token = try PaceDataObject.authenticationTokenInput(
      for: BrainpoolP384r1.generator,
      suite: PaceInfo(mapping: .generic, domain: .brainpoolP384r1)
    )
    let bytes = Array(token)
    #expect(Array(bytes[5..<15]) == PaceValues.protocolOidBody)
  }
}
