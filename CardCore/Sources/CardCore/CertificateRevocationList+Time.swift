// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension CertificateRevocationList {
  /// Standard textual encoding boundary for a PEM CRL.
  private static let pemBegin = "-----BEGIN X509 CRL-----"

  /// Standard textual encoding boundary for a PEM CRL.
  private static let pemEnd = "-----END X509 CRL-----"

  /// The two PEM boundary lines surrounding the Base64 body.
  private static let pemBoundaryLineCount = 2

  /// Converts standard PEM input to DER while leaving DER input unchanged.
  internal static func derEncoded(from input: Data) throws -> Data {
    if input.first == DerValues.sequenceTagByte {
      return input
    }
    guard let text = String(data: input, encoding: .ascii) else {
      throw ValidationFailure.malformed
    }
    let lines = text.split(omittingEmptySubsequences: false) { character in
      character.isNewline
    }
    let trimmed =
      lines
      .map { line in
        line.trimmingCharacters(in: CharacterSet.whitespaces)
      }
      .filter { line in !line.isEmpty }
    guard
      trimmed.first == Self.pemBegin,
      trimmed.last == Self.pemEnd,
      trimmed.count > Self.pemBoundaryLineCount
    else {
      throw ValidationFailure.malformed
    }
    let body = trimmed.dropFirst().dropLast()
    guard
      body.allSatisfy({ !$0.hasPrefix("-----") }),
      let decoded = Data(base64Encoded: body.joined()),
      !decoded.isEmpty
    else {
      throw ValidationFailure.malformed
    }
    return decoded
  }

  /// Parses RFC 5280's exact whole-second UTC time forms.
  internal static func time(
    in reader: DerReader,
    element: DerReader.Element
  ) throws -> Date {
    guard let date = DerTime.rfc5280Time(in: reader, element: element) else {
      throw ValidationFailure.malformed
    }
    return date
  }

  /// Rejects future or expired lists at the caller's verification time.
  internal static func checkTimes(
    _ list: ParsedList,
    nextUpdate: Date,
    against currentTime: Date
  ) throws {
    guard list.thisUpdate <= currentTime else {
      throw ValidationFailure.listFromFuture
    }
    guard
      nextUpdate > list.thisUpdate,
      nextUpdate > currentTime
    else {
      throw ValidationFailure.listExpired
    }
  }
}
