// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import zlib

/// Raw DEFLATE (RFC 1951) and PDF FlateDecode (RFC 1950 wrapper) decompression via zlib.
internal enum FlateDecoder {
  /// Outcome of inflating a raw DEFLATE entry with a declared uncompressed size.
  internal enum ExactInflateResult {
    /// Decompressed to the declared size after consuming every input byte.
    case decoded(Data)

    /// Stream produced fewer or more bytes than declared.
    case lengthMismatch

    /// Stream failed to initialize or decode as valid raw DEFLATE.
    case malformed
  }

  /// Outcome of draining a raw DEFLATE stream up to a byte ceiling.
  private enum DrainOutcome {
    case finished(Data, unconsumedBytes: Int)
    case limitExceeded
    case malformed
  }

  /// Bytes in the RFC 1950 wrapper's header.
  private static let headerLength = 2

  /// The method nibble deflate uses in the header's first byte.
  private static let deflateMethod = 8

  /// Mask selecting the method nibble.
  private static let methodMask = 15

  /// Bit shift to the `CINFO` window-size nibble in the RFC 1950 `CMF` byte.
  private static let cinfoShift = 4

  /// Maximum `CINFO` value permitted for DEFLATE (`32 KiB` window, RFC 1950 §2.2).
  private static let maxDeflateWindowInfo = 7

  /// The header bit announcing a preset dictionary, which FlateDecode
  /// never uses.
  private static let presetDictionaryBit = 32

  /// The modulus the header's check word satisfies.
  private static let checkModulus = 31

  /// Bytes drained from the decoder per round.
  private static let chunkLength = 65_536

  /// Inflates `input`, refusing output beyond `limit` bytes.
  ///
  /// The wrapper is stripped and the body decoded raw, so the
  /// trailing Adler-32 is not verified - which also accepts the bare
  /// deflate body some writers emit.
  internal static func decoded(_ input: Data, limit: Int) -> Data? {
    guard limit >= 0, let body = Self.deflateBody(of: input), !body.isEmpty else { return nil }
    guard case .finished(let data, _) = Self.drain(Data(body), limit: limit) else { return nil }
    return data
  }

  /// Inflates raw DEFLATE `compressed` into `expectedCount` bytes, requiring full input consumption.
  internal static func inflateRawExact(_ compressed: Data, expectedCount: Int) -> ExactInflateResult
  {
    guard expectedCount >= 0 else { return .malformed }
    switch Self.drain(compressed, limit: expectedCount) {
    case .finished(let data, let unconsumedBytes):
      guard unconsumedBytes == 0 else { return .malformed }
      return data.count == expectedCount ? .decoded(data) : .lengthMismatch

    case .limitExceeded:
      return .lengthMismatch

    case .malformed:
      return .malformed
    }
  }

  /// Opens `stream` as a raw RFC 1951 DEFLATE decoder.
  private static func openRawInflate(_ stream: inout z_stream) -> Bool {
    inflateInit2_(
      &stream,
      ZipValues.zlibRawDeflateWindowBits,
      ZLIB_VERSION,
      Int32(MemoryLayout<z_stream>.size)
    ) == Z_OK
  }

  /// The deflate body inside `input`, unwrapped when an RFC 1950
  /// header leads it.
  private static func deflateBody(of input: Data) -> Data.SubSequence? {
    guard input.count >= Self.headerLength else { return nil }
    let first = Int(input[input.startIndex])
    let second = Int(input[input.startIndex + 1])
    let checkWord = (first << UInt8.bitWidth) | second
    let isWrapped =
      (first & Self.methodMask) == Self.deflateMethod
      && checkWord.isMultiple(of: Self.checkModulus)
    guard isWrapped else { return input[...] }
    guard
      (first >> Self.cinfoShift) <= Self.maxDeflateWindowInfo,
      second & Self.presetDictionaryBit == 0
    else {
      return nil
    }
    return input.dropFirst(Self.headerLength)
  }

  /// Inflates raw DEFLATE `compressed` chunk by chunk up to `limit` bytes.
  private static func drain(_ compressed: Data, limit: Int) -> DrainOutcome {
    guard !compressed.isEmpty else { return .malformed }
    var stream = z_stream()
    guard Self.openRawInflate(&stream) else { return .malformed }
    defer { inflateEnd(&stream) }

    return compressed.withUnsafeBytes { srcBuffer in
      Self.drainBuffer(&stream, source: srcBuffer, limit: limit)
    }
  }

  /// Feeds `source` in chunks and drains output until `Z_STREAM_END` or `limit` is exceeded.
  private static func drainBuffer(
    _ stream: inout z_stream,
    source: UnsafeRawBufferPointer,
    limit: Int
  ) -> DrainOutcome {
    guard let srcBase = source.baseAddress?.assumingMemoryBound(to: Bytef.self) else {
      return .malformed
    }
    var output = Data()
    var scratch = [UInt8](repeating: 0, count: Self.chunkLength)
    var inOffset = 0
    while true {
      if stream.avail_in == 0, inOffset < source.count {
        let feed = min(source.count - inOffset, Int(uInt.max))
        stream.next_in = UnsafeMutablePointer(mutating: srcBase.advanced(by: inOffset))
        stream.avail_in = uInt(feed)
        inOffset += feed
      }
      let status: Int32 = scratch.withUnsafeMutableBufferPointer { buffer in
        stream.next_out = buffer.baseAddress
        stream.avail_out = uInt(Self.chunkLength)
        return inflate(&stream, Z_NO_FLUSH)
      }
      guard status == Z_OK || status == Z_STREAM_END else { return .malformed }
      let produced = Self.chunkLength - Int(stream.avail_out)
      if produced > 0 {
        guard output.count + produced <= limit else { return .limitExceeded }
        output.append(contentsOf: scratch.prefix(produced))
      }
      if status == Z_STREAM_END {
        let unconsumed = (source.count - inOffset) + Int(stream.avail_in)
        return .finished(output, unconsumedBytes: unconsumed)
      }
      if produced == 0, stream.avail_in == 0, inOffset >= source.count {
        return .malformed
      }
    }
  }
}
