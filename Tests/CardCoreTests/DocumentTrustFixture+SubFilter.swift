// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// Rewriting the subfilter of a prepared signature revision.
  extension DocumentTrustFixture {
    /// `placeholder` with the written subfilter after `offset` replaced
    /// by `subFilter` of the same length.
    internal static func replacingSubFilter(
      in placeholder: PdfSignaturePlaceholder,
      with subFilter: String,
      after offset: Int
    ) throws -> PdfSignaturePlaceholder {
      var bytes = placeholder.document
      let marker = try #require(
        bytes[offset...].range(of: Data(Self.writtenSubFilter.utf8)))
      try #require(subFilter.utf8.count == Self.writtenSubFilter.utf8.count)
      bytes.replaceSubrange(marker, with: Data(subFilter.utf8))
      return PdfSignaturePlaceholder(
        document: bytes,
        contentsOpen: placeholder.contentsOpen,
        secondSpanStart: placeholder.secondSpanStart,
        capacity: placeholder.capacity
      )
    }
  }

#endif
