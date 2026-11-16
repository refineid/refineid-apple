// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// PNG row predictor decoding for PDF streams (ISO 32000-1 §7.4.4.4).
extension PdfStreamObject {
  /// The predictor value meaning none was applied.
  private static let noPredictor = 1

  /// The first of the PNG row predictors (ISO 32000-1 §7.4.4.4);
  /// values below it other than none are the TIFF predictor, which
  /// this reader does not decode.
  private static let pngPredictorFloor = 10

  /// PNG row filter: the row as written.
  private static let pngFilterNone = 0

  /// PNG row filter: each byte relative to its left neighbour.
  private static let pngFilterSub = 1

  /// PNG row filter: each byte relative to the byte above.
  private static let pngFilterUp = 2

  /// PNG row filter: each byte relative to the mean of left and above.
  private static let pngFilterAverage = 3

  /// PNG row filter: each byte relative to the Paeth prediction.
  private static let pngFilterPaeth = 4

  /// Divisor of the average filter's prediction.
  private static let averageDivisor = 2

  /// The samples-per-byte shape this reader decodes: one colour of
  /// eight bits, which is what cross-reference streams use.
  private static let supportedColors = 1

  /// Bits per component in the supported shape.
  private static let supportedBitsPerComponent = 8

  /// Undoes the row predictor `/DecodeParms` names (ISO 32000-1
  /// §7.4.4.4).
  internal static func unpredicted(
    _ data: Data,
    syntax: PdfValidationStore.DictionarySyntax
  ) throws -> Data {
    guard let parms = try Self.decodeParameters(in: syntax) else {
      return data
    }
    guard
      let predictor = Self.parameterInteger(named: "Predictor", in: parms),
      predictor != Self.noPredictor
    else {
      return data
    }
    guard predictor >= Self.pngPredictorFloor else {
      throw PdfSigningError.crossReferenceStreamUnsupported
    }
    if let colors = Self.parameterInteger(named: "Colors", in: parms),
      colors != Self.supportedColors
    {
      throw PdfSigningError.crossReferenceStreamUnsupported
    }
    if let bits = Self.parameterInteger(named: "BitsPerComponent", in: parms),
      bits != Self.supportedBitsPerComponent
    {
      throw PdfSigningError.crossReferenceStreamUnsupported
    }
    let columns: Int
    if parms.entry(named: "Columns") != nil {
      guard let parsedColumns = Self.parameterInteger(named: "Columns", in: parms)
      else {
        throw PdfSigningError.structureUnreadable
      }
      columns = parsedColumns
    } else {
      columns = 1
    }
    return try Self.pngUnfiltered(data, columns: columns)
  }

  /// Resolves `/DecodeParms` when it is null, a direct dictionary, or a
  /// one-element array wrapping either (ISO 32000-1 Table 5).
  private static func decodeParameters(
    in syntax: PdfValidationStore.DictionarySyntax
  ) throws -> PdfValidationStore.DictionarySyntax? {
    guard let entry = syntax.entry(named: "DecodeParms") else { return nil }
    let raw = syntax.value(of: entry)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if raw == "null" { return nil }
    if let direct = try? PdfValidationStore.DictionarySyntax(raw) {
      return direct
    }
    if let single = Self.singleElementArrayBody(in: raw) {
      if single == "null" { return nil }
      if let nested = try? PdfValidationStore.DictionarySyntax(single) {
        return nested
      }
    }
    throw PdfSigningError.crossReferenceStreamUnsupported
  }

  /// Extracts the sole element when `raw` is `[ element ]`.
  private static func singleElementArrayBody(in raw: String) -> String? {
    guard let data = raw.data(using: .isoLatin1) else { return nil }
    var parser = PdfValidationStore.ValueParser(data)
    parser.skipTrivia()
    guard parser.consume("[") else { return nil }
    parser.skipTrivia()
    let start = parser.offset
    if parser.has("<<") {
      guard (try? parser.dictionary()) != nil else { return nil }
    } else {
      guard (try? parser.atom()) != nil else { return nil }
    }
    let end = parser.offset
    parser.skipTrivia()
    guard parser.consume("]"), (try? parser.requireEnd()) != nil else {
      return nil
    }
    return PdfValidationStore.ValueLexemes.text(data.subdata(in: start..<end))
  }

  /// Reads an unsigned integer parameter from `/DecodeParms`.
  private static func parameterInteger(
    named name: String,
    in parms: PdfValidationStore.DictionarySyntax
  ) -> Int? {
    guard let entry = parms.entry(named: name) else { return nil }
    return PdfValidationStore.TypedValues.unsignedInteger(
      in: parms.value(of: entry)
    )
  }

  /// Undoes the per-row PNG filters over one-byte samples.
  private static func pngUnfiltered(
    _ data: Data,
    columns: Int
  ) throws -> Data {
    let (rowStride, overflow) = columns.addingReportingOverflow(1)
    guard !overflow, columns > 0 else {
      throw PdfSigningError.structureUnreadable
    }
    if data.isEmpty { return Data() }
    guard columns <= data.count, data.count.isMultiple(of: rowStride) else {
      throw PdfSigningError.structureUnreadable
    }
    var output = Data(capacity: data.count - data.count / rowStride)
    var above = Data(repeating: 0, count: columns)
    var cursor = data.startIndex
    while cursor < data.endIndex {
      let filter = Int(data[cursor])
      let row = data.subdata(in: (cursor + 1)..<(cursor + rowStride))
      cursor += rowStride
      let decoded = try Self.unfilteredRow(row, filter: filter, above: above)
      output.append(decoded)
      above = decoded
    }
    return output
  }

  /// One row with its filter undone.
  private static func unfilteredRow(
    _ row: Data,
    filter: Int,
    above: Data
  ) throws -> Data {
    var decoded = Data(repeating: 0, count: row.count)
    for column in 0..<row.count {
      let left = column > 0 ? decoded[column - 1] : 0
      let upper = above[column]
      let upperLeft = column > 0 ? above[column - 1] : 0
      let prediction: UInt8
      switch filter {
      case Self.pngFilterNone:
        prediction = 0

      case Self.pngFilterSub:
        prediction = left

      case Self.pngFilterUp:
        prediction = upper

      case Self.pngFilterAverage:
        prediction = UInt8(
          (Int(left) + Int(upper)) / Self.averageDivisor
        )

      case Self.pngFilterPaeth:
        prediction = Self.paeth(
          left: left, above: upper, upperLeft: upperLeft
        )

      default:
        throw PdfSigningError.structureUnreadable
      }
      decoded[column] = row[column] &+ prediction
    }
    return decoded
  }

  /// The Paeth prediction: whichever neighbour is closest to the
  /// initial estimate `left + above - upperLeft`.
  private static func paeth(
    left: UInt8,
    above: UInt8,
    upperLeft: UInt8
  ) -> UInt8 {
    let estimate = Int(left) + Int(above) - Int(upperLeft)
    let distanceLeft = abs(estimate - Int(left))
    let distanceAbove = abs(estimate - Int(above))
    let distanceUpperLeft = abs(estimate - Int(upperLeft))
    if distanceLeft <= distanceAbove, distanceLeft <= distanceUpperLeft {
      return left
    }
    if distanceAbove <= distanceUpperLeft {
      return above
    }
    return upperLeft
  }
}
