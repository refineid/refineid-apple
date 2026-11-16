// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Locates the signatures of an existing PDF (ISO 32000-1 section 12.8).
///
/// The byte ranges declared by each signature dictionary define the two
/// signed spans and, between them, the hex hole carrying the CMS; the
/// reader trusts the declaration only after checking it against the
/// file's actual bytes: the hole is exactly this dictionary's own
/// `/Contents` string, and everything after the DER inside it is zero
/// padding (ISO 32000-1 clause 12.8.1).
public enum PdfSignatureReader {
  /// One signature found in the document.
  public struct FoundSignature: Sendable {
    /// The CMS ContentInfo carried in the hole, padding removed.
    public let cms: Data

    /// The declared /SubFilter.
    public let subFilter: PdfSubFilter

    /// The two declared byte-range spans.
    internal let signedSpans: PdfSignaturePlaceholder

    /// Whether the spans cover the entire file, which the final
    /// signature of a document always does.
    public let coversWholeDocument: Bool

    /// Whether the spans end where a revision ends: just after an
    /// `%%EOF` marker and at most one end-of-line (ISO 32000-1 clause
    /// 7.5.5).
    public let endsRevision: Bool

    /// The digest of the two declared byte-range spans.
    public func byteRangeDigest(_ algorithm: DocumentDigestAlgorithm) -> Data {
      signedSpans.digest(algorithm)
    }
  }

  /// A signature paired with the indirect object identity where it was
  /// located in the cross-reference history.
  internal struct LocatedSignature: Sendable {
    /// The indirect object's number.
    internal let objectNumber: Int

    /// Where that revision placed the signature dictionary.
    internal let location: PdfDocumentIndex.ObjectLocation

    /// The parsed signature dictionary and CMS payload.
    internal let signature: FoundSignature
  }

  /// Why a located signature could not be read.
  public enum Failure: Error, Sendable {
    case documentTooLarge
    case malformedByteRange
    case malformedContents
  }

  /// Every readable signature in the document, in object order.
  ///
  /// Objects without both `/ByteRange` and `/Contents` are not signatures
  /// and are skipped; a signature candidate whose declaration does not
  /// match the file throws instead of degrading into a partial answer.
  public static func signatures(
    in document: Data
  ) throws -> [FoundSignature] {
    try Self.signatures(
      in: document,
      maximumByteCount: PdfValues.maximumVerifiedDocumentByteCount
    )
  }

  /// The same, refusing a document longer than `maximumByteCount`
  /// before any of it is read.
  internal static func signatures(
    in input: Data,
    maximumByteCount: Int
  ) throws -> [FoundSignature] {
    let located = try Self.locatedSignatures(
      in: input,
      maximumByteCount: maximumByteCount
    )
    return located.map(\.signature)
  }

  /// Every readable signature across the cross-reference chain, paired
  /// with its object number and location.
  internal static func locatedSignatures(
    in input: Data,
    maximumByteCount: Int
  ) throws -> [LocatedSignature] {
    guard input.count <= maximumByteCount else {
      throw Failure.documentTooLarge
    }
    let document = Data(input)
    let index = try PdfDocumentIndex.parse(document)
    var found: [LocatedSignature] = []
    for item in index.historicalObjects {
      guard
        let body = index.body(of: item.number, at: item.location, in: document),
        body.contains("/"),
        body.contains("ByteRange") || body.contains("#"),
        !PdfTypeEntry.hasStream(body)
      else {
        continue
      }
      guard let syntax = try? PdfValidationStore.DictionarySyntax(body) else {
        if body.contains("/ByteRange"), body.contains("/Contents") {
          throw Failure.malformedByteRange
        }
        continue
      }
      guard
        syntax.entry(named: "ByteRange") != nil,
        let contents = syntax.entry(named: "Contents")
      else {
        continue
      }
      let contentsInFile = try Self.fileRange(
        of: contents.valueRange,
        body: body,
        objectNumber: item.number,
        location: item.location,
        in: document
      )
      let parsed = try Self.signature(
        declaredBy: body,
        syntax: syntax,
        contentsInFile: contentsInFile,
        in: document
      )
      found.append(
        LocatedSignature(
          objectNumber: item.number,
          location: item.location,
          signature: parsed
        )
      )
    }
    return found
  }
}
