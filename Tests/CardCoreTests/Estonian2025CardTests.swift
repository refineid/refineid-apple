// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// EstEID 2025 (Thales MultiApp v5.1, GED24035) card protocol, identity,
/// directory discovery, signing, and credential management tests.
@Suite
internal struct Estonian2025CardTests {
  internal static let estonianAllowance = EstonianEidValues.pinRetryLimit
  private static let binaryChipSerial = Data([.zero, .max, .zero, .max])
  private static let binaryChipSerialHex: String =
    binaryChipSerial
    .map { byte in String(format: "%02X", byte) }
    .joined()

  @Test
  internal func pkcs15DirectoryParsesAuthObjectsPathsAndKeyUsage() {
    let locations = Pkcs15Directory.locations(
      fromObjectDirectory: EstonianEidTestFixture.objectDirectory()
    )
    #expect(locations.authObjects == .estonian2025Aod)
    #expect(locations.certificates == EstonianEidTestFixture.certificateDirectoryFile)
    #expect(locations.privateKeys == EstonianEidTestFixture.privateKeyDirectoryFile)

    let certs = Pkcs15Directory.certificates(
      fromDirectory: EstonianEidTestFixture.certificateDirectory()
    )
    #expect(certs.count == 2)
    #expect(
      certs[0].path == [.estonianAwpDirectory, EstonianEidTestFixture.rekeyedAuthCertFile]
    )
    #expect(
      certs[1].path == [.estonianQscdDirectory, EstonianEidTestFixture.rekeyedSignCertFile]
    )

    let keys = Pkcs15Directory.privateKeys(
      fromDirectory: EstonianEidTestFixture.privateKeyDirectory()
    )
    #expect(keys.count == 2)
    #expect(keys[0].usage == .sign)
    #expect(keys[0].keyReference == EstonianEidTestFixture.rekeyedAuthKeyRef)
    #expect(keys[1].usage == .nonRepudiation)
    #expect(keys[1].keyReference == EstonianEidTestFixture.rekeyedSignKeyRef)
  }

  @Test
  internal func pin2ProbeFirstStillResolvesEstonian2025ViaPin1() throws {
    let three = try #require(RetryCount(attemptsRemaining: Self.estonianAllowance))
    let threeRemaining = try EstonianEidTestFixture.remaining(Self.estonianAllowance)
    let channel = TypedScriptedChannel([
      (
        CommandApdu.readRetryCounter(role: .pin1, references: .citizen).encoded,
        EstonianEidTestFixture.status(.referenceDataNotFound)
      ),
      (
        CommandApdu.readRetryCounter(role: .pin1, references: .organization).encoded,
        EstonianEidTestFixture.status(.referenceDataNotFound)
      ),
      (
        CommandApdu.readRetryCounter(role: .pin1, references: .estonian2025).encoded,
        EstonianEidTestFixture.status(threeRemaining)
      ),
      (
        CommandApdu.readRetryCounter(role: .pin2, references: .estonian2025).encoded,
        EstonianEidTestFixture.status(threeRemaining)
      ),
    ])
    let operations = CardOperations(channel: channel)
    #expect(try operations.probeRetryCounter(role: .pin2) == .remaining(three))
    #expect(operations.resolvedNumbering == .estonian2025)
    #expect(operations.pristineRetryAllowance == Self.estonianAllowance)
    #expect(channel.isExhausted)
  }

  @Test
  internal func estonian2025IdentitySerialsSeparateChipSerialAndDocumentNumber() throws {
    let threeRemaining = try EstonianEidTestFixture.remaining(Self.estonianAllowance)
    let tokenInfo = EstonianEidTestFixture.tokenInfo(serialBytes: Self.binaryChipSerial)
    let docBytes = Data(EstonianEidTestFixture.syntheticDocNumber2025.utf8)
    let selectDocPath = try #require(
      CommandApdu.selectByPath([.estonianDocumentDataDirectory, .estonianDocumentNumberPlain])
    )
    let plainRead = try EstonianEidTestFixture.readBinary(
      offset: .zero, count: ReadChunkLength.plain.count
    )
    let capRead = try EstonianEidTestFixture.readBinary(
      offset: .zero, count: DocumentNumber.probeReadCap
    )
    let maxRead = try EstonianEidTestFixture.readBinary(
      offset: .zero, count: ExpectedResponseLength.maximum
    )
    let success = EstonianEidTestFixture.status(.success)
    let channel = TypedScriptedChannel([
      (
        CommandApdu.readRetryCounter(role: .pin1, references: .citizen).encoded,
        EstonianEidTestFixture.status(.referenceDataNotFound)
      ),
      (
        CommandApdu.readRetryCounter(role: .pin1, references: .organization).encoded,
        EstonianEidTestFixture.status(.referenceDataNotFound)
      ),
      (
        CommandApdu.readRetryCounter(role: .pin1, references: .estonian2025).encoded,
        EstonianEidTestFixture.status(threeRemaining)
      ),
      (EstonianEidTestFixture.selectEf(.tokenInfo), success),
      (plainRead, EstonianEidTestFixture.response(tokenInfo, status: .success)),
      (EstonianEidTestFixture.selectApp, success),
      (selectDocPath.encoded, success),
      (capRead, EstonianEidTestFixture.status(.endOfFile)),
      (maxRead, EstonianEidTestFixture.response(docBytes, status: .success)),
      (EstonianEidTestFixture.selectApp, success),
    ])
    let serials = try CardOperations(channel: channel).readCardIdentitySerials()
    #expect(serials.chipSerial.value == Self.binaryChipSerialHex)
    #expect(serials.printedSerial.value == EstonianEidTestFixture.syntheticDocNumber2025)
    #expect(
      TokenInstanceID(printedSerial: serials.printedSerial).value == "refineid-card-aa0000001")
    #expect(channel.isExhausted)
  }

  @Test
  internal func estonian2025DiscoversRekeyedCertificates() throws {
    let success = EstonianEidTestFixture.status(.success)
    let plainRead = try EstonianEidTestFixture.readBinary(
      offset: .zero, count: ReadChunkLength.plain.count
    )
    let authPath = try #require(
      CommandApdu.selectByPath([.estonianAwpDirectory, EstonianEidTestFixture.rekeyedAuthCertFile])
    )
    let signPath = try #require(
      CommandApdu.selectByPath([.estonianQscdDirectory, EstonianEidTestFixture.rekeyedSignCertFile])
    )
    let authResponse = EstonianEidTestFixture.response(
      EstonianEidTestFixture.syntheticAuthCertDer, status: .success
    )
    let signResponse = EstonianEidTestFixture.response(
      EstonianEidTestFixture.syntheticSignCertDer, status: .success
    )
    var script: [(Data, Data)] = [(EstonianEidTestFixture.selectApp, success)]
    script.append(
      contentsOf: EstonianEidTestFixture.estonian2025DiscoveryExchanges(plainRead: plainRead))
    script.append(contentsOf: [
      (authPath.encoded, success), (plainRead, authResponse),
      (EstonianEidTestFixture.selectApp, success),
      (EstonianEidTestFixture.selectApp, success),
      (signPath.encoded, success), (plainRead, signResponse),
      (EstonianEidTestFixture.selectApp, success),
    ])
    let channel = TypedScriptedChannel(script)
    let operations = CardOperations(channel: channel, numbering: .estonian2025)
    #expect(
      try operations.readCertificate(.authentication) == EstonianEidTestFixture.syntheticAuthCertDer
    )
    #expect(
      try operations.readCertificate(.qualifiedSignature)
        == EstonianEidTestFixture.syntheticSignCertDer
    )
    #expect(throws: CardOperationError.selectRejected(.fileNotFound)) {
      _ = try operations.readCertificate(.issuing)
    }
    #expect(channel.isExhausted)
  }

  @Test
  internal func estonian2025ReadsPinLengthsFromAod() throws {
    let success = EstonianEidTestFixture.status(.success)
    let plainRead = try EstonianEidTestFixture.readBinary(
      offset: .zero, count: ReadChunkLength.plain.count
    )
    var script: [(Data, Data)] = [(EstonianEidTestFixture.selectApp, success)]
    script.append(
      contentsOf: EstonianEidTestFixture.estonian2025DiscoveryExchanges(plainRead: plainRead))
    script.append(contentsOf: [
      (EstonianEidTestFixture.selectEf(.estonian2025Aod), success),
      (
        plainRead,
        EstonianEidTestFixture.response(EstonianEidTestFixture.estonian2025Aod(), status: .success)
      ),
    ])
    let channel = TypedScriptedChannel(script)
    let operations = CardOperations(channel: channel, numbering: .estonian2025)
    let lengths = try operations.readCardPinLengths()
    EstonianEidTestFixture.expectStandardEstonianPinLengths(lengths)
    #expect(channel.isExhausted)
  }

  @Test
  internal func estonian2025SignsWithDiscoveredRekeyedKeyReferences() throws {
    let digest = Data(repeating: UInt8(ascii: "H"), count: EstonianEidValues.p384DigestLength)
    let algorithm = SigningAlgorithm(hash: .sha384, scheme: .ecdsa)
    let sigLength = try #require(
      ExpectedResponseLength(count: EstonianEidTestFixture.p384RawSignatureLength)
    )
    let channel = TypedScriptedChannel(
      try Self.estonian2025SigningScript(digest: digest, algorithm: algorithm, sigLength: sigLength)
    )
    let operations = CardOperations(channel: channel, numbering: .estonian2025)
    guard
      let pin1 = Pin1(digits: EstonianEidTestFixture.samplePin1),
      let pin2 = Pin2(digits: EstonianEidTestFixture.samplePin2)
    else {
      Issue.record("synthetic PIN failed to construct")
      return
    }
    try operations.verifyPin1(pin1.consumeForSingleTransmission())
    let authSig = try operations.computeAuthenticationSignature(
      overDigest: digest, algorithm: algorithm, expectedSignatureLength: sigLength
    )
    #expect(authSig == EstonianEidTestFixture.syntheticSignatureBytes)
    try operations.verifyPin2(pin2.consumeForSingleTransmission())
    let signSig = try operations.computeQualifiedSignature(
      overDigest: digest, algorithm: algorithm, expectedSignatureLength: sigLength
    )
    #expect(signSig == EstonianEidTestFixture.syntheticSignatureBytes)
    #expect(channel.isExhausted)
  }
}
