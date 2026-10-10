// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import XCTest

@testable import CardCore
@testable import RappEngine

/// Tests the BLE transport framing, routing preamble, profile parameters,
/// and endpoint definitions.
internal final class BleRelayTests: XCTestCase {

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

  internal func testBlePairingPreambleNamesThePairingPurpose() throws {
    let preamble = try rappPairingPreamble(transportProfile: RappBleGattProfile.name)
    XCTAssertEqual(RappBleRoutingPurpose(preamble: preamble), .pairing)
    XCTAssertNil(RappBleRoutingPurpose(preamble: Data("noise".utf8)))
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
