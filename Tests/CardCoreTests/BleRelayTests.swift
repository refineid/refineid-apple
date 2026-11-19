// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore
@testable import RappEngine

/// Tests the BLE transport framing, routing preamble, profile parameters,
/// and endpoint definitions.
@Suite(.serialized)
internal final class BleRelayTests {

  @Test
  internal func testBleFramingBounds() throws {
    let payload = Data("ble-payload-test".utf8)
    let framed = try #require(BleRelayFraming.encode(payload))
    #expect((framed.count) == (BleRelayFraming.lengthPrefixByteCount + payload.count))
    #expect(
      (BleRelayFraming.payloadByteCount(
        lengthPrefix: framed.prefix(BleRelayFraming.lengthPrefixByteCount)
      )) == (payload.count))

    let largest = Data(count: BleRelayFraming.maximumPayloadByteCount)
    #expect((BleRelayFraming.encode(largest)) != nil)
    let oversized = Data(count: BleRelayFraming.maximumPayloadByteCount + 1)
    #expect((BleRelayFraming.encode(oversized)) == nil)
    #expect((BleRelayFraming.encode(Data())) == nil)

    let zeroLengthPrefix = Data(count: BleRelayFraming.lengthPrefixByteCount)
    #expect((BleRelayFraming.payloadByteCount(lengthPrefix: zeroLengthPrefix)) == nil)
    #expect((BleRelayFraming.payloadByteCount(lengthPrefix: Data())) == nil)
  }

  @Test
  internal func testBlePairingPreambleNamesThePairingPurpose() throws {
    let preamble = try rappPairingPreamble(transportProfile: RappBleGattProfile.name)
    #expect((RappBleRoutingPurpose(preamble: preamble)) == (.pairing))
    #expect((RappBleRoutingPurpose(preamble: Data("noise".utf8))) == nil)
  }

  @Test
  internal func testBleEndpointDefaults() {
    let endpoint = BleRelayEndpoint()
    #expect((endpoint.serviceUUIDString) == ("FA1D0001-C34A-4836-843B-7603B5749A32"))
    #expect((endpoint.psm) == nil)

    let custom = BleRelayEndpoint(
      serviceUUIDString: "12345678-1234-1234-1234-123456789ABC", psm: 42)
    #expect((custom.serviceUUIDString) == ("12345678-1234-1234-1234-123456789ABC"))
    #expect((custom.psm) == (42))
  }
}
