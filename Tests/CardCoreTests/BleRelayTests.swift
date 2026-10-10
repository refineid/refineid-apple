// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import XCTest

@testable import CardCore
@testable import RappEngine

/// Tests the BLE transport framing, rendezvous encoding/decoding, profile parameters,
/// and endpoint definitions.
internal final class BleRelayTests: XCTestCase {
  private static let testToken = Data(repeating: 0x42, count: 16)

  internal func testBleFramingBounds() throws {
    let payload = Data("ble-payload-test".utf8)
    let framed = try XCTUnwrap(BleRelayFraming.encode(payload))
    XCTAssertEqual(framed.count, BleRelayFraming.lengthPrefixByteCount + payload.count)
    XCTAssertEqual(
      BleRelayFraming.payloadByteCount(
        lengthPrefix: framed.prefix(BleRelayFraming.lengthPrefixByteCount)
      ),
      payload.count
    )

    let largest = Data(count: BleRelayFraming.maximumPayloadByteCount)
    XCTAssertNotNil(BleRelayFraming.encode(largest))
    let oversized = Data(count: BleRelayFraming.maximumPayloadByteCount + 1)
    XCTAssertNil(BleRelayFraming.encode(oversized))
    XCTAssertNil(BleRelayFraming.encode(Data()))

    let zeroLengthPrefix = Data(count: BleRelayFraming.lengthPrefixByteCount)
    XCTAssertNil(BleRelayFraming.payloadByteCount(lengthPrefix: zeroLengthPrefix))
    XCTAssertNil(BleRelayFraming.payloadByteCount(lengthPrefix: Data()))
  }

  internal func testBleRendezvousPairingEncoding() throws {
    let preamble = rappBlePairingPreamble()
    XCTAssertFalse(preamble.isEmpty)

    let decoded = try BleRendezvous.decode(preamble)
    XCTAssertEqual(decoded, .pairing)
  }

  internal func testBleRendezvousSessionEncoding() throws {
    let preamble = try rappBleSessionPreamble(rendezvousToken: Self.testToken)
    XCTAssertFalse(preamble.isEmpty)

    let decoded = try BleRendezvous.decode(preamble)
    XCTAssertEqual(decoded, .session(token: Self.testToken))
  }

  internal func testBleCandidateParametersEncoding() throws {
    let params = try rappBleCandidateParameters(
      serviceUUID: BleProfile.defaultServiceUUIDString,
      psm: 128
    )
    XCTAssertFalse(params.isEmpty)
  }

  internal func testBleEndpointDefaults() {
    let endpoint = BleRelayEndpoint()
    XCTAssertEqual(endpoint.serviceUUIDString, "FA1D0001-C34A-4836-843B-7603B5749A32")
    XCTAssertNil(endpoint.psm)

    let custom = BleRelayEndpoint(
      serviceUUIDString: "12345678-1234-1234-1234-123456789ABC", psm: 42)
    XCTAssertEqual(custom.serviceUUIDString, "12345678-1234-1234-1234-123456789ABC")
    XCTAssertEqual(custom.psm, 42)
  }
}
