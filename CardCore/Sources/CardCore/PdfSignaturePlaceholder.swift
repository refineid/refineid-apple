// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A prepared PDF revision with a reserved, fixed-size hole for one
/// signature or document timestamp (ISO 32000-1 §12.8, ETSI EN 319
/// 142-1).
///
/// The order is forced by the format and there is no other order: the
/// revision is written first, its /ByteRange patched to the final
/// offsets, and only then is anything digested - because the digest
/// covers the file with the hole in it. Writing into the hole never
/// changes a length, so the digest stays true.
public struct PdfSignaturePlaceholder: Sendable {
  /// The document with the hole, byte ranges already patched.
  public let document: Data

  /// Where the hex hole's `<` sits.
  internal let contentsOpen: Int

  /// The first byte after the hole's `>`.
  internal let secondSpanStart: Int

  /// Bytes available inside the hole, before hex expansion.
  internal let capacity: Int

  /// The two spans the signature covers, concatenated: everything
  /// before the hole and everything after it.
  public var signedOctets: Data {
    document.prefix(contentsOpen) + document.suffix(from: secondSpanStart)
  }

  /// The digest of those spans - what the card signs, and what a
  /// document timestamp is taken over.
  public func digest(_ algorithm: DocumentDigestAlgorithm) -> Data {
    algorithm.hash(signedOctets)
  }

  /// Writes `der` into the hole, hex-encoded uppercase, leaving the
  /// rest of the hole as the zero padding it already is.
  ///
  /// The file's length is unchanged by construction, so every offset
  /// and both byte ranges remain exactly as digested.
  public func filled(with der: Data) throws -> Data {
    guard der.count <= capacity else {
      throw PdfSigningError.signatureTooLarge(
        needed: der.count, reserved: capacity
      )
    }
    var out = document
    let digits = Array(PdfValues.hexDigits.utf8)
    var cursor = contentsOpen + 1
    for byte in der {
      out[cursor] = digits[Int(byte >> PdfValues.hexDigitBits)]
      out[cursor + 1] = digits[Int(byte & PdfValues.hexDigitMask)]
      cursor += PdfValues.hexCharactersPerByte
    }
    return out
  }
}
