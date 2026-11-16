// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension OcspResponse {
  /// Parses the RFC 5280 GeneralizedTime profile used by OCSP.
  internal static func generalizedTime(
    in reader: DerReader,
    element: DerReader.Element
  ) throws -> Date {
    guard let date = DerTime.rfc5280GeneralizedTime(in: reader, element: element) else {
      throw ValidationFailure.malformed
    }
    return date
  }

  /// Reads nextUpdate's explicit wrapper.
  internal static func explicitGeneralizedTime(
    in encoded: Data,
    wrapper: DerReader.Element
  ) throws -> Date {
    var reader = DerReader(encoded, within: wrapper)
    let time = try Self.requiredElement(
      from: &reader,
      tag: DerValues.tagGeneralizedTime
    )
    guard reader.isAtEnd else { throw ValidationFailure.malformed }
    return try Self.generalizedTime(in: reader, element: time)
  }

  /// Rejects future or expired evidence before it can become LT material.
  internal static func checkTimes(
    _ response: ResponseData,
    against currentTime: Date
  ) throws {
    let latestPermitted = currentTime.addingTimeInterval(Self.maximumClockSkew)
    guard
      response.producedAt <= latestPermitted,
      response.thisUpdate <= latestPermitted
    else {
      throw ValidationFailure.responseFromFuture
    }
    guard response.thisUpdate <= response.producedAt.addingTimeInterval(Self.maximumClockSkew)
    else {
      throw ValidationFailure.responseFromFuture
    }
    if let nextUpdate = response.nextUpdate {
      guard
        nextUpdate > response.thisUpdate,
        nextUpdate > currentTime.addingTimeInterval(-Self.maximumClockSkew)
      else {
        throw ValidationFailure.responseExpired
      }
    } else {
      guard
        currentTime.timeIntervalSince(response.thisUpdate)
          <= Self.maximumAgeWithoutNextUpdate + Self.maximumClockSkew
      else {
        throw ValidationFailure.responseExpired
      }
    }
  }
}
