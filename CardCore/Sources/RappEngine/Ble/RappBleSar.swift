// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The RAPP BLE segmentation and reassembly framing (RAPP v26.10.9 §5.3).
///
/// Every message on the Channel Characteristic travels as one or more
/// fragments, each a 6-byte header (total length, chunk sequence, flags,
/// reserved) followed by payload. This type sends; ``RappBleSarReassembler``
/// receives. Neither touches a radio.
public enum RappBleSar {
  /// Header field offsets and widths.
  internal enum Field {
    internal static let totalLength = 0
    internal static let sequence = 2
    internal static let flags = 4
    internal static let reserved = 5
  }

  /// Fragment flag values: bit 0 FIRST, bit 1 CONT, bit 2 LAST.
  internal enum Flag {
    internal static let first: UInt8 = 1 << 0
    internal static let continuation: UInt8 = 1 << 1
    internal static let last: UInt8 = 1 << 2
    internal static let single: UInt8 = first | last
    /// Bits 0 to 2; bits 3 to 7 are reserved.
    internal static let allDefined: UInt8 = first | continuation | last
  }

  /// Bytes in one fragment header.
  public static let headerSize = 6
  /// The smallest negotiated ATT MTU the profile accepts.
  public static let minimumAttMtu = 512
  /// The fewest payload bytes a FIRST or CONT fragment may carry.
  public static let minimumNonFinalPayload = 64
  /// The first chunk sequence that is out of bounds.
  public static let sequenceLimit = 1_024
  /// The longest message the 16-bit total length expresses.
  public static let maximumMessageLength = Int(UInt16.max)
  /// How long a frame may take to reassemble after its FIRST fragment.
  public static let reassemblyTimeoutMilliseconds: UInt64 = 5_000

  /// The hard cap on any attribute value (Bluetooth Core v5.4, Vol 3,
  /// Part F, §3.2.9).
  internal static let attributeValueLimit = 512
  /// Bytes the ATT PDU header takes from the MTU.
  internal static let attHeaderSize = 3

  /// Bits per byte in the big-endian header fields.
  private static let bitsPerByte = 8
  /// Mask selecting the low byte of a header field.
  private static let lowByteMask = Int(UInt8.max)

  /// The uniform fragment payload capacity:
  /// `min(negotiated_att_mtu - 3, 512) - 6`, also bounded by any smaller
  /// value limit the platform reports.
  ///
  /// - Throws: ``RappBleSarError/attMtuTooSmall`` below an MTU of 512, and
  ///   ``RappBleSarError/invalidCapacity`` when the platform limit leaves
  ///   no room for a non-final fragment.
  public static func payloadCapacity(
    negotiatedAttMtu: Int, platformValueLimit: Int? = nil
  ) throws -> Int {
    guard negotiatedAttMtu >= minimumAttMtu else { throw RappBleSarError.attMtuTooSmall }
    var valueLimit = min(negotiatedAttMtu - attHeaderSize, attributeValueLimit)
    if let platformValueLimit {
      valueLimit = min(valueLimit, platformValueLimit)
    }
    let capacity = valueLimit - headerSize
    guard capacity >= minimumNonFinalPayload else { throw RappBleSarError.invalidCapacity }
    return capacity
  }

  /// Splits one message into the fragments that carry it, in order.
  ///
  /// A message that fits one fragment travels as SINGLE; a longer one as
  /// FIRST, CONT ... and LAST, each non-final fragment filled to capacity.
  public static func segment(_ message: Data, capacity: Int) throws -> [Data] {
    guard capacity >= minimumNonFinalPayload,
      capacity <= attributeValueLimit - headerSize
    else { throw RappBleSarError.invalidCapacity }
    guard !message.isEmpty, message.count <= maximumMessageLength else {
      throw RappBleSarError.invalidMessageLength
    }
    let bytes = Data(message)
    guard bytes.count > capacity else {
      return [fragment(total: bytes.count, sequence: 0, flags: Flag.single, payload: bytes)]
    }
    var fragments: [Data] = []
    var offset = 0
    while offset < bytes.count {
      let end = min(offset + capacity, bytes.count)
      let flags: UInt8
      if offset == 0 {
        flags = Flag.first
      } else if end == bytes.count {
        flags = Flag.last
      } else {
        flags = Flag.continuation
      }
      fragments.append(
        fragment(
          total: bytes.count, sequence: fragments.count, flags: flags,
          payload: bytes.subdata(in: offset..<end)))
      offset = end
    }
    return fragments
  }

  private static func fragment(
    total: Int, sequence: Int, flags: UInt8, payload: Data
  ) -> Data {
    var data = Data(capacity: headerSize + payload.count)
    data.append(contentsOf: bigEndian(total))
    data.append(contentsOf: bigEndian(sequence))
    data.append(flags)
    data.append(0)
    data.append(contentsOf: payload)
    return data
  }

  private static func bigEndian(_ value: Int) -> Data {
    Data([UInt8(value >> bitsPerByte & lowByteMask), UInt8(value & lowByteMask)])
  }

  /// Reads one big-endian 16-bit header field of a fragment.
  internal static func field(_ fragment: Data, at offset: Int) -> Int {
    let start = fragment.startIndex + offset
    return Int(fragment[start]) << bitsPerByte | Int(fragment[start + 1])
  }
}
