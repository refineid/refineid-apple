// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Testing

@testable import CardCore

extension DerTimeTests {
  @Test
  internal func nonZeroBasedDataSlicesParseAcrossAllProfiles() {
    let base = Date(timeIntervalSince1970: Self.sampleInstant)
    let slicedUtc = Data("X260804074633Z".utf8).dropFirst()
    let slicedGeneralized = Data("X20260804074633Z".utf8).dropFirst()
    let slicedFractional = Data("X20260804074633.125Z".utf8).dropFirst()

    #expect(DerTime.rfc5280Time(tag: DerValues.tagUtcTime, content: slicedUtc) == base)
    #expect(
      DerTime.rfc5280Time(tag: DerValues.tagGeneralizedTime, content: slicedGeneralized) == base
    )
    #expect(DerTime.rfc5280GeneralizedTime(slicedGeneralized) == base)
    #expect(
      DerTime.rfc3161GeneralizedTime(slicedFractional)
        == base.addingTimeInterval(Self.eighthSecond)
    )
  }

  @Test
  internal func scsJsonWebSignatureRejectsMalformedAndTrailingByteCertificates() throws {
    let material = ScsTestCertificate.make(
      notBefore: "260101000000Z",
      notAfter: "270101000000Z"
    )
    let signingInput = Data("eyJhbGciOiJFUzI1NiJ9.eyJ2ZXJzaW9uIjoiMS4zIn0".utf8)
    let signature = try material.key.signature(for: signingInput).rawRepresentation
    let insideWindow = Date(timeIntervalSince1970: Self.sampleInstant)

    #expect(
      ScsJsonWebSignature.refusal(
        algorithm: "ES256",
        certificateDer: material.der,
        signingInput: signingInput,
        signature: signature,
        at: insideWindow
      ) == nil
    )

    let garbageRefusal = ScsJsonWebSignature.refusal(
      algorithm: "ES256",
      certificateDer: Data("not-der".utf8),
      signingInput: signingInput,
      signature: signature,
      at: insideWindow
    )
    #expect(garbageRefusal == .badRequest("serverCert is not DER X.509"))

    var trailingDer = material.der
    trailingDer.append(DerValues.asciiZero)
    let trailingRefusal = ScsJsonWebSignature.refusal(
      algorithm: "ES256",
      certificateDer: trailingDer,
      signingInput: signingInput,
      signature: signature,
      at: insideWindow
    )
    #expect(trailingRefusal == .badRequest("serverCert is not DER X.509"))
  }

  @Test
  internal func nonZuluTimezonesAndNonDigitsAreRejected() {
    let nonZuluGeneralized = [
      "",
      "20260804074633",
      "20260804074633z",
      "20260804074633+0000",
      "20260804074633-0200",
      "20260804074633+0200Z",
      "2026080407463aZ",
    ]
    for text in nonZuluGeneralized {
      #expect(
        Self.parseRfc5280GeneralizedTime(tag: DerValues.tagGeneralizedTime, text) == nil,
        "\(text) was accepted by rfc5280GeneralizedTime"
      )
      #expect(
        Self.parseRfc5280Time(tag: DerValues.tagGeneralizedTime, text) == nil,
        "\(text) was accepted by rfc5280Time"
      )
      #expect(
        DerTime.rfc3161GeneralizedTime(Data(text.utf8)) == nil,
        "\(text) was accepted by rfc3161GeneralizedTime"
      )
    }

    let nonZuluUtc = [
      "",
      "260804074633",
      "260804074633z",
      "260804074633+0000",
      "26080407463aZ",
    ]
    for text in nonZuluUtc {
      #expect(
        Self.parseRfc5280Time(tag: DerValues.tagUtcTime, text) == nil,
        "\(text) was accepted as UTCTime"
      )
    }
  }
}
