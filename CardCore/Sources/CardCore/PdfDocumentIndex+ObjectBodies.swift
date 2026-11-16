// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Reading indirect object bodies from verified direct offsets or object
/// streams.
extension PdfDocumentIndex {
  /// The bytes between a verified `N G obj` header and its closing
  /// `endobj` for a non-stream indirect object.
  private static func nonStreamDirectBody(
    of number: Int,
    generation: Int,
    at offset: Int,
    in document: Data
  ) -> String? {
    guard offset >= 0, offset < document.count else { return nil }
    let bytes = PdfBytes(document)
    guard
      let headerEnd = bytes.objectHeaderEnd(
        at: offset,
        expectedNumber: number,
        expectedGeneration: generation
      ),
      !Self.looksLikeStreamObject(in: bytes, afterHeader: headerEnd),
      let endRange = bytes.keywordTokenRange(
        of: PdfValues.endObjectKeyword,
        from: headerEnd
      )
    else {
      return nil
    }
    return bytes.text(in: headerEnd..<endRange.lowerBound)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Whether the dictionary opening at `headerEnd` is immediately
  /// followed by a `stream` keyword.
  private static func looksLikeStreamObject(
    in bytes: PdfBytes,
    afterHeader headerEnd: Int
  ) -> Bool {
    guard let dictionary = bytes.balancedDictionary(from: headerEnd) else {
      return false
    }
    let keywordAt = bytes.skippingTrivia(from: dictionary.end)
    return bytes.hasKeywordToken(PdfValues.streamKeyword, at: keywordAt)
  }

  /// The object number of an indirect reference in `dictionary` whose
  /// generation matches the live table in `self`.
  internal func verifiedReference(
    named key: String,
    in dictionary: String
  ) -> Int? {
    guard
      let parsed = Self.fullReference(named: key, in: dictionary),
      let location = locations[parsed.number],
      location.generation == parsed.generation
    else {
      return nil
    }
    return parsed.number
  }

  /// The object number of a generation-zero indirect reference in
  /// `dictionary` that is live at generation zero in `self`.
  internal func zeroGenVerifiedReference(
    named key: String,
    in dictionary: String
  ) -> Int? {
    guard
      let parsed = Self.fullReference(named: key, in: dictionary),
      parsed.generation == 0,
      let location = locations[parsed.number],
      location.generation == 0
    else {
      return nil
    }
    return parsed.number
  }

  /// One object's body in the live table: the bytes between `obj` and
  /// `endobj`, or its slice of the object stream carrying it.
  internal func body(of number: Int, in document: Data) -> String? {
    guard let location = locations[number] else { return nil }
    return body(of: number, at: location, in: document)
  }

  /// One object's body at a specific location, verifying its indirect
  /// object header when direct.
  internal func body(
    of number: Int,
    at location: ObjectLocation,
    in document: Data
  ) -> String? {
    switch location {
    case .direct(let offset, let generation):
      return directBody(
        of: number,
        generation: generation,
        at: offset,
        in: document
      )

    case .compressed(let container, let position):
      return compressedBody(
        of: number, container: container, position: position, in: document
      )
    }
  }

  /// One object's bytes for comparing two revisions of a document.
  ///
  /// A stream is taken by its `/Length` and unfiltered when supported,
  /// not by the first `endobj` in the file: stream data is free to spell
  /// that word, and reading to it would let a rewrite past it look
  /// unchanged.
  internal func comparisonBody(of number: Int, in document: Data) -> String? {
    switch locations[number] {
    case .direct(let offset, let generation):
      return directComparisonBody(
        of: number,
        generation: generation,
        at: offset,
        in: document
      )

    case .compressed(let container, let position):
      return compressedBody(
        of: number, container: container, position: position, in: document
      )

    case nil:
      return nil
    }
  }

  /// The bytes between a verified `N G obj` header and its matching
  /// `endobj`, honoring direct or indirect stream `/Length`.
  private func directBody(
    of number: Int,
    generation: Int,
    at offset: Int,
    in document: Data
  ) -> String? {
    guard offset >= 0, offset < document.count else { return nil }
    let bytes = PdfBytes(document)
    guard
      let headerEnd = bytes.objectHeaderEnd(
        at: offset,
        expectedNumber: number,
        expectedGeneration: generation
      )
    else {
      return nil
    }
    if Self.looksLikeStreamObject(in: bytes, afterHeader: headerEnd) {
      guard
        let span = try? PdfStreamObject.rawSpan(
          in: bytes,
          at: offset,
          expectedNumber: number,
          expectedGeneration: generation,
          resolveLength: { reference in
            self.resolvedStreamLength(reference, in: document)
          }
        )
      else {
        return nil
      }
      return bytes.text(in: headerEnd..<span.endObjectStart)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return Self.nonStreamDirectBody(
      of: number, generation: generation, at: offset, in: document
    )
  }

  /// One direct object's bytes for comparison across revisions.
  private func directComparisonBody(
    of number: Int,
    generation: Int,
    at offset: Int,
    in document: Data
  ) -> String? {
    guard offset >= 0, offset < document.count else { return nil }
    let bytes = PdfBytes(document)
    guard
      let headerEnd = bytes.objectHeaderEnd(
        at: offset,
        expectedNumber: number,
        expectedGeneration: generation
      )
    else {
      return nil
    }
    if Self.looksLikeStreamObject(in: bytes, afterHeader: headerEnd) {
      return streamComparisonBody(
        of: number, generation: generation, at: offset, in: document
      )
    }
    return Self.nonStreamDirectBody(
      of: number, generation: generation, at: offset, in: document
    )
  }

  /// Normalizes a stream object for revision comparison, falling back to
  /// raw stream bytes when a syntactically valid non-Flate filter is used.
  private func streamComparisonBody(
    of number: Int,
    generation: Int,
    at offset: Int,
    in document: Data
  ) -> String? {
    let bytes = PdfBytes(document)
    guard
      let span = try? PdfStreamObject.rawSpan(
        in: bytes,
        at: offset,
        expectedNumber: number,
        expectedGeneration: generation,
        resolveLength: { reference in
          self.resolvedStreamLength(reference, in: document)
        }
      )
    else {
      return nil
    }
    let rawPayload = bytes.data(in: span.payloadRange)
    do {
      let decoded = try PdfStreamObject.decoded(
        rawPayload, dictionary: span.dictionary
      )
      guard let payload = String(bytes: decoded, encoding: .isoLatin1) else {
        return nil
      }
      return (span.dictionary + "\nstream\n" + payload)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    } catch PdfSigningError.crossReferenceStreamUnsupported {
      let rawText = bytes.text(in: span.payloadRange)
      return (span.dictionary + "\nstream\n" + rawText)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      return nil
    }
  }

  /// Resolves an indirect stream `/Length` integer from a non-stream object.
  private func resolvedStreamLength(
    _ reference: PdfValidationStore.StoreReference,
    in document: Data
  ) -> Int? {
    guard
      let location = locations[reference.number],
      location.generation == reference.generation
    else {
      return nil
    }
    let text: String?
    switch location {
    case .direct(let offset, let generation):
      text = Self.nonStreamDirectBody(
        of: reference.number,
        generation: generation,
        at: offset,
        in: document
      )
    case .compressed(let container, let position):
      text = compressedBody(
        of: reference.number,
        container: container,
        position: position,
        in: document
      )
    }
    guard let text else { return nil }
    return PdfValidationStore.TypedValues.unsignedInteger(in: text)
  }
}
