// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Cuts the bytes one stream connection received into its length-prefixed
/// frames (RAPP v26.10.22 §2.2.2).
internal struct StreamFrameReader: Sendable {
  /// Bytes received and not yet part of a whole frame.
  private var pending = Data()

  /// Takes `received` and answers the frames it completed, in order.
  ///
  /// - Throws: ``StreamRelayTransportError/malformedFrame`` when a length
  ///   prefix declares no valid frame, which ends the connection.
  internal mutating func frames(after received: Data) throws(StreamRelayTransportError)
    -> [Data]
  {
    pending.append(received)
    var frames: [Data] = []
    while pending.count >= StreamRelayFraming.lengthPrefixByteCount {
      let prefix = Data(pending.prefix(StreamRelayFraming.lengthPrefixByteCount))
      guard let length = StreamRelayFraming.payloadByteCount(lengthPrefix: prefix) else {
        throw .malformedFrame
      }
      let total = StreamRelayFraming.lengthPrefixByteCount + length
      guard pending.count >= total else { break }
      let body = pending.dropFirst(StreamRelayFraming.lengthPrefixByteCount)
      frames.append(Data(body.prefix(length)))
      pending = Data(pending.dropFirst(total))
    }
    return frames
  }
}
