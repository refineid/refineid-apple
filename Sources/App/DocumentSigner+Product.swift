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
    internal let signatureTimestampTime: Date

    /// Bytes built on `signature`, which carries their signature timestamp.
    internal init(bytes: Data, completion: Completion, signature: TimestampedSignature) {
      self.bytes = bytes
      self.completion = completion
      self.signatureTimestampTime = signature.signatureTimestampTime
    }
  }

  /// What evidence was completed after the card signature.
  internal enum Completion: Equatable, Sendable {
    /// Complete PAdES-B-LTA evidence.
    case archival

    #if DEBUG
      /// Debug-only PAdES-B-T output from an authenticated revoked signer.
      case revokedSignerTest
    #endif
  }
}
