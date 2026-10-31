// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension OcspResponse {
  /// Checks response extensions and, when a nonce was sent, that an
  /// echoed nonce equals it.
  internal static func checkResponseExtensions(
    in encoded: Data,
    wrapper: DerReader.Element,
    expectedNonce: Data?
  ) throws {
    var echoedNonce: Data?
    var seenOids: Set<Data> = []
    for extensionValue in try Self.extensions(in: encoded, wrapper: wrapper) {
      guard seenOids.insert(extensionValue.oid).inserted else {
        throw ValidationFailure.malformed
      }
      if extensionValue.oid == DerEncoder.objectIdentifier(SignOids.ocspNonce) {
        guard echoedNonce == nil else { throw ValidationFailure.malformed }
        let nonce = try Self.onlyElement(
          in: extensionValue.value,
          tag: DerValues.tagOctetString
        )
        echoedNonce = DerReader(extensionValue.value).contentData(of: nonce)
      } else if extensionValue.critical {
        throw ValidationFailure.unsupportedCriticalExtension
      }
    }
    if let expectedNonce, let echoedNonce, echoedNonce != expectedNonce {
      throw ValidationFailure.nonceMismatch
    }
  }

  /// Parses the Extensions sequence inside one explicit context wrapper.
  internal static func extensions(
    in encoded: Data,
    wrapper: DerReader.Element
  ) throws -> [Extension] {
    var wrapperReader = DerReader(encoded, within: wrapper)
    let sequence = try Self.requiredElement(
      from: &wrapperReader,
      tag: DerValues.tagSequence
    )
    guard wrapperReader.isAtEnd else { throw ValidationFailure.malformed }
    var reader = DerReader(encoded, within: sequence)
    var values: [Extension] = []
    while let element = reader.next() {
      guard element.tag == DerValues.tagSequence else {
        throw ValidationFailure.malformed
      }
      values.append(try Self.extensionValue(in: encoded, element: element))
    }
    guard reader.isAtEnd, !values.isEmpty else { throw ValidationFailure.malformed }
    return values
  }

  /// Parses one RFC 5280 Extension.
  internal static func extensionValue(
    in encoded: Data,
    element: DerReader.Element
  ) throws -> Extension {
    var reader = DerReader(encoded, within: element)
    let oid = try Self.requiredElement(
      from: &reader,
      tag: DerValues.tagObjectIdentifier
    )
    var next = try Self.requiredElement(from: &reader)
    var critical = false
    if next.tag == DerValues.tagBoolean {
      let value = reader.contentData(of: next)
      guard value == Data([DerValues.booleanTrue]) else {
        throw ValidationFailure.malformed
      }
      critical = true
      next = try Self.requiredElement(from: &reader)
    }
    guard next.tag == DerValues.tagOctetString, reader.isAtEnd else {
      throw ValidationFailure.malformed
    }
    return Extension(
      critical: critical,
      oid: reader.data(of: oid),
      value: reader.contentData(of: next)
    )
  }

  /// Rejects a critical extension unless this verifier has processed it.
  internal static func rejectUnknownCriticalExtensions(
    _ extensions: [Extension]
  ) throws {
    guard !extensions.contains(where: \.critical) else {
      throw ValidationFailure.unsupportedCriticalExtension
    }
  }
}
