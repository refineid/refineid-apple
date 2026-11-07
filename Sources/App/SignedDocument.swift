// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A finished signature held in memory until it is written.
internal struct SignedDocument: Sendable {
  /// The signed bytes.
  internal let bytes: Data

  /// The best signature time (ETSI EN 319 102-1 clause 5.5): the
  /// generation time of the signature timestamp, or the clock for a
  /// signature that carries none.
  internal let bestSignatureTime: Date

  #if DEBUG
    /// The level a development signature stopped at, when below the
    /// long-term level.
    internal private(set) var belowLongTerm: BelowLongTermSignature?
  #endif

  /// What the output's name carries before its extension: nothing for
  /// a long-term signature.
  internal var nameMarker: String {
    #if DEBUG
      belowLongTerm?.nameMarker ?? SignedDocumentName.longTermMarker
    #else
      SignedDocumentName.longTermMarker
    #endif
  }

  /// A signature named by its signature timestamp.
  internal init(bytes: Data, signatureTimestampTime: Date) {
    self.bytes = bytes
    self.bestSignatureTime = signatureTimestampTime
  }

  /// A signed PDF, named by its signature timestamp and, in a
  /// development build, by the level it reached.
  internal init(_ product: DocumentSigner.Product) {
    #if DEBUG
      self.init(
        bytes: product.bytes,
        signatureTimestampTime: product.signatureTimestampTime,
        belowLongTerm: product.completion.shortfall
      )
    #else
      self.init(bytes: product.bytes, signatureTimestampTime: product.signatureTimestampTime)
    #endif
  }

  /// A signed container, named by its signature timestamp and, in a
  /// development build, by the level it reached.
  internal init(_ container: AsicSigner.Product) {
    #if DEBUG
      self.init(
        bytes: container.bytes,
        signatureTimestampTime: container.signatureTimestampTime,
        belowLongTerm: container.belowLongTerm
      )
    #else
      self.init(
        bytes: container.bytes, signatureTimestampTime: container.signatureTimestampTime
      )
    #endif
  }

  #if DEBUG
    /// A development signature, kept below the long-term level when
    /// `belowLongTerm` is set.
    internal init(
      bytes: Data,
      signatureTimestampTime: Date,
      belowLongTerm: BelowLongTermSignature?
    ) {
      self.bytes = bytes
      self.bestSignatureTime = signatureTimestampTime
      self.belowLongTerm = belowLongTerm
    }
  #endif

  /// A signature that carries no timestamp, named by the clock.
  internal init(untimestamped bytes: Data, clock: Date) {
    self.bytes = bytes
    self.bestSignatureTime = clock
  }
}
