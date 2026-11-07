// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The signed bytes and the validation level actually completed.
extension DocumentSigner {
  /// One completed document-signing operation.
  internal struct Product: Sendable {
    /// The finished PDF bytes.
    internal let bytes: Data

    /// The evidence level present in those bytes.
    internal let completion: Completion

    /// The generation time of the signature's own timestamp; a
    /// document timestamp over the finished file never sets it.
    ///
    /// A development signature without a timestamp carries the clock.
    internal let signatureTimestampTime: Date

    /// Bytes built on `signature`, which carries their signature timestamp.
    internal init(bytes: Data, completion: Completion, signature: TimestampedSignature) {
      self.bytes = bytes
      self.completion = completion
      self.signatureTimestampTime = signature.signatureTimestampTime
    }

    #if DEBUG
      /// Development bytes that carry no signature timestamp, named by
      /// `clock`.
      internal init(basic bytes: Data, clock: Date, shortfall: BelowLongTermSignature) {
        self.bytes = bytes
        self.completion = .belowLongTerm(shortfall)
        self.signatureTimestampTime = clock
      }
    #endif
  }

  /// What evidence was completed after the card signature.
  internal enum Completion: Equatable, Sendable {
    /// Complete PAdES-B-LTA evidence.
    case archival

    #if DEBUG
      /// A development signature kept below PAdES-B-LTA.
      case belowLongTerm(BelowLongTermSignature)

      /// The level a development signature stopped at, if below
      /// PAdES-B-LTA.
      internal var shortfall: BelowLongTermSignature? {
        guard case .belowLongTerm(let shortfall) = self else { return nil }
        return shortfall
      }
    #endif
  }
}
