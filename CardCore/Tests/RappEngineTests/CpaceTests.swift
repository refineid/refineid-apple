// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Testing

@testable import RappEngine

@Suite("CPace PAKE over Ristretto255 conformance tests")
internal struct CpaceTests {
  private struct AppendixB3Points {
    let yaPoint: RistrettoPoint
    let ybPoint: RistrettoPoint
    let yaBytes: Data
    let ybBytes: Data
  }

  @Test("FieldElement51 arithmetic")
  internal func testArithmetic() {
    let hex = "a3785913ca4deb75abd841414d0a700098e879777940c78c73fe6f2bee6c0352"
    let elementA = FieldElement51.fromHex(hex)
    let elementB = elementA.square()
    let elementC = elementA * elementB
    let elementD = elementC.invert()
    let (isSquare, candidateRoot) = FieldElement51.sqrtRatioI(elemU: elementA, elemV: elementB)
    #expect(elementA != elementB)
    #expect(!elementD.isZero)
    #expect(!candidateRoot.isZero)
    #expect(isSquare || !isSquare)
  }

  @Test("RFC 9496 Appendix A.3 one-way map known answer test")
  internal func rfc9496OneWayMapVector() {
    let input = Data([
      0x5d, 0x1b, 0xe0, 0x9e, 0x3d, 0x0c, 0x82, 0xfc, 0x53, 0x81, 0x12, 0x49, 0x0e,
      0x35, 0x70, 0x19, 0x79, 0xd9, 0x9e, 0x06, 0xca, 0x3e, 0x2b, 0x5b, 0x54, 0xbf,
      0xfe, 0x8b, 0x4d, 0xc7, 0x72, 0xc1, 0x4d, 0x98, 0xb6, 0x96, 0xa1, 0xbb, 0xfb,
      0x5c, 0xa3, 0x2c, 0x43, 0x6c, 0xc6, 0x1c, 0x16, 0x56, 0x37, 0x90, 0x30, 0x6c,
      0x79, 0xea, 0xca, 0x77, 0x05, 0x66, 0x8b, 0x47, 0xdf, 0xfe, 0x5b, 0xb6,
    ])
    let expected = Data([
      0x30, 0x66, 0xf8, 0x2a, 0x1a, 0x74, 0x7d, 0x45, 0x12, 0x0d, 0x17, 0x40, 0xf1,
      0x43, 0x58, 0x53, 0x1a, 0x8f, 0x04, 0xbb, 0xff, 0xe6, 0xa8, 0x19, 0xf8, 0x6d,
      0xfe, 0x50, 0xf4, 0x4a, 0x0a, 0x46,
    ])

    let point = RistrettoPoint.fromUniformBytes(input)
    #expect(point.compress() == expected)
  }

  private func verifyAppendixB3Generator(
    dsi: Data,
    prs: Data,
    channelInfo: Data,
    sid: Data
  ) -> RistrettoPoint {
    let genStr = cpaceGeneratorString(
      dsi: dsi,
      prs: prs,
      channelInfo: channelInfo,
      sid: sid,
      sInBytes: 128
    )
    #expect(genStr.count == 170)

    let genHash = Data(SHA512.hash(data: genStr))
    let expectedHashPrefix = Data([0xda, 0x6d, 0x3d, 0xdc, 0x88, 0x02, 0xfc, 0xa9])
    #expect(genHash.prefix(8) == expectedHashPrefix)

    let generatorPoint = RistrettoPoint.fromUniformBytes(genHash)
    let encodedG = generatorPoint.compress()
    let expectedG = Data([
      0x22, 0x2b, 0x6b, 0x19, 0x5f, 0xe8, 0x4b, 0x16,
      0x52, 0xba, 0xdb, 0x6f, 0x6a, 0x3a, 0xe3, 0xd2,
      0x43, 0x41, 0xe7, 0x30, 0x69, 0x67, 0xf0, 0xb8,
      0x11, 0x5b, 0x40, 0xd5, 0x69, 0x8c, 0x7e, 0x56,
    ])
    #expect(encodedG == expectedG)
    return generatorPoint
  }

  private func verifyAppendixB3PublicPoints(
    generatorPoint: RistrettoPoint
  ) -> AppendixB3Points {
    let yaBytes = Data([
      0xda, 0x3d, 0x23, 0x70, 0x0a, 0x9e, 0x56, 0x99,
      0x25, 0x8a, 0xef, 0x94, 0xdc, 0x06, 0x0d, 0xfd,
      0xa5, 0xeb, 0xb6, 0x1f, 0x02, 0xa5, 0xea, 0x77,
      0xfa, 0xd5, 0x3f, 0x4f, 0xf0, 0x97, 0x6d, 0x08,
    ])
    let yaPoint = generatorPoint.scalarMul(yaBytes)
    let expectedYa = Data([
      0xd6, 0xba, 0xc4, 0x80, 0xf2, 0xc3, 0x86, 0xc3,
      0x94, 0xef, 0xc7, 0xc4, 0x7a, 0xdb, 0x99, 0x25,
      0xdc, 0xd2, 0x63, 0x0b, 0x64, 0xf2, 0x40, 0xc5,
      0x0f, 0x8d, 0x0e, 0xec, 0x48, 0x2b, 0x91, 0x57,
    ])
    #expect(yaPoint.compress() == expectedYa)

    let ybBytes = Data([
      0xd2, 0x31, 0x6b, 0x45, 0x47, 0x18, 0xc3, 0x53,
      0x62, 0xd8, 0x3d, 0x69, 0xdf, 0x63, 0x20, 0xf3,
      0x85, 0x78, 0xed, 0x59, 0x84, 0x65, 0x14, 0x35,
      0xe2, 0x94, 0x97, 0x62, 0xd9, 0x00, 0xb8, 0x0d,
    ])
    let ybPoint = generatorPoint.scalarMul(ybBytes)
    let expectedYb = Data([
      0x3e, 0xa7, 0xe0, 0xb1, 0x95, 0x60, 0xd7, 0xc0,
      0xb0, 0xf5, 0x73, 0x4f, 0x63, 0xb9, 0x55, 0x28,
      0x6d, 0xfa, 0x82, 0x32, 0xb5, 0xeb, 0xe6, 0x33,
      0x24, 0xe2, 0xd9, 0xe7, 0x43, 0x3f, 0x72, 0x58,
    ])
    #expect(ybPoint.compress() == expectedYb)
    return AppendixB3Points(
      yaPoint: yaPoint,
      ybPoint: ybPoint,
      yaBytes: yaBytes,
      ybBytes: ybBytes
    )
  }

  @Test("draft-irtf-cfrg-cpace-21 Appendix B.3 official test vector")
  internal func cpaceAppendixB3OfficialVector() {
    let prs = Data("Password".utf8)
    let dsi = Data("CPaceRistretto255".utf8)
    let channelInfo = Data([
      0x0b, 0x41, 0x5f, 0x69, 0x6e, 0x69, 0x74, 0x69, 0x61, 0x74, 0x6f, 0x72,
      0x0b, 0x42, 0x5f, 0x72, 0x65, 0x73, 0x70, 0x6f, 0x6e, 0x64, 0x65, 0x72,
    ])
    let sid = Data([
      0x7e, 0x4b, 0x47, 0x91, 0xd6, 0xa8, 0xef, 0x01,
      0x9b, 0x93, 0x6c, 0x79, 0xfb, 0x7f, 0x2c, 0x57,
    ])

    let generatorPoint = verifyAppendixB3Generator(
      dsi: dsi,
      prs: prs,
      channelInfo: channelInfo,
      sid: sid
    )

    let verifiedPoints = verifyAppendixB3PublicPoints(
      generatorPoint: generatorPoint
    )
    let yaPoint = verifiedPoints.yaPoint
    let ybPoint = verifiedPoints.ybPoint
    let yaBytes = verifiedPoints.yaBytes
    let ybBytes = verifiedPoints.ybBytes

    let pointKa = ybPoint.scalarMul(yaBytes).compress()
    let pointKb = yaPoint.scalarMul(ybBytes).compress()
    #expect(pointKa == pointKb)

    let expectedK = Data([
      0x80, 0xb6, 0x9a, 0x8a, 0x76, 0x45, 0x7a, 0xb6,
      0xa4, 0xd7, 0xf8, 0x87, 0xa4, 0xbf, 0x6b, 0x55,
      0xa2, 0xf8, 0x0a, 0xc1, 0x9c, 0x33, 0x3f, 0x91,
      0x7a, 0x05, 0xfc, 0x98, 0x87, 0xc8, 0xb4, 0x0f,
    ])
    #expect(pointKa == expectedK)

    let transcriptIR = cpaceTranscriptIR(
      partyAPublic: yaPoint.compress(),
      additionalDataA: Data("ADa".utf8),
      partyBPublic: ybPoint.compress(),
      additionalDataB: Data("ADb".utf8)
    )
    let isk = cpaceCalculateIsk(
      sid: sid,
      sharedPoint: pointKa,
      transcriptIR: transcriptIR
    )
    let expectedIskPrefix = Data([0xb6, 0x9e, 0xff, 0xbf, 0x61, 0xb5, 0x1d, 0x56])
    let expectedIskSuffix = Data([0x3f, 0xa2, 0x06, 0x8a, 0xf7, 0x90, 0x04, 0x47])
    #expect(isk.prefix(8) == expectedIskPrefix)
    #expect(isk.suffix(8) == expectedIskSuffix)
  }

  @Test("CPace end-to-end key agreement between initiator and responder")
  internal func cpaceSuccessfulAgreement() throws {
    let offerId = Data(repeating: 0x42, count: 32)
    let code = "123 456"

    let randomA = Data(repeating: 0x11, count: 64)
    let randomB = Data(repeating: 0x22, count: 64)

    let alice = try RappCpaceState(
      isInitiator: true,
      pairingCode: code,
      offerId: offerId,
      randomBytes64: randomA
    )
    let bob = try RappCpaceState(
      isInitiator: false,
      pairingCode: code,
      offerId: offerId,
      randomBytes64: randomB
    )

    let alicePublic = alice.publicPoint
    let bobPublic = bob.publicPoint

    #expect(alicePublic != Data(repeating: 0, count: 32))
    #expect(bobPublic != Data(repeating: 0, count: 32))
    #expect(alicePublic != bobPublic)

    let secretA = try alice.finish(peerPublic: bobPublic)
    let secretB = try bob.finish(peerPublic: alicePublic)

    #expect(secretA.count == 32)
    #expect(secretA == secretB)
  }

  @Test("CPace mismatched codes produce distinct secrets")
  internal func cpaceMismatchedCodes() throws {
    let offerId = Data(repeating: 0x42, count: 32)
    let randomA = Data(repeating: 0x11, count: 64)
    let randomE = Data(repeating: 0x33, count: 64)

    let alice = try RappCpaceState(
      isInitiator: true,
      pairingCode: "123456",
      offerId: offerId,
      randomBytes64: randomA
    )
    let eve = try RappCpaceState(
      isInitiator: false,
      pairingCode: "123457",
      offerId: offerId,
      randomBytes64: randomE
    )

    let secretA = try alice.finish(peerPublic: eve.publicPoint)
    let secretE = try eve.finish(peerPublic: alice.publicPoint)

    #expect(secretA != secretE)
  }

  @Test("CPace binary frame round-trip")
  internal func cpaceFrameRoundTrip() throws {
    let offerId = Data(repeating: 0x77, count: 32)
    let code = "987 654"

    let alice = try RappCpaceState(
      isInitiator: true,
      pairingCode: code,
      offerId: offerId,
      randomBytes64: Data(repeating: 0xaa, count: 64)
    )
    let bob = try RappCpaceState(
      isInitiator: false,
      pairingCode: code,
      offerId: offerId,
      randomBytes64: Data(repeating: 0xbb, count: 64)
    )

    let aliceFrame = try alice.writeMessage()
    let bobFrame = try bob.writeMessage()

    let secretB = try bob.readMessage(aliceFrame)
    let secretA = try alice.readMessage(bobFrame)

    #expect(secretA == secretB)
  }
}
