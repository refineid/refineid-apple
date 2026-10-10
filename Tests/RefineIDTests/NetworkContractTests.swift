// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

/// The outbound network contract, pinned.
///
/// New traffic-capable code, a changed Bluetooth declaration, or a
/// changed ATS shape fails here on purpose: update the contract in
/// `Documentation/decisions.md` (2026-09-30, 2026-10-09) first, then
/// this list.
@Suite
internal struct NetworkContractTests {
  private static var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  /// First-party Swift sources, relative to the repository root.
  private static func swiftFiles() -> [String] {
    let roots = ["Sources", "CardCore/Sources", "PKCS11Bridge/Sources"]
    var found: [String] = []
    for directory in roots {
      let url = root.appending(path: directory)
      guard
        let enumerator = FileManager.default.enumerator(
          at: url, includingPropertiesForKeys: [.isRegularFileKey]
        )
      else { continue }
      for item in enumerator {
        guard let file = item as? URL, file.pathExtension == "swift" else {
          continue
        }
        let prefix = root.path + "/"
        guard file.path.hasPrefix(prefix) else { continue }
        found.append(String(file.path.dropFirst(prefix.count)))
      }
    }
    return found.sorted()
  }

  /// Sources whose text names any of the tokens.
  private static func files(containingAny tokens: [String]) throws -> Set<String> {
    var found = Set<String>()
    for relative in Self.swiftFiles() {
      let text = try String(
        contentsOf: root.appending(path: relative), encoding: .utf8
      )
      if tokens.contains(where: text.contains) {
        found.insert(relative)
      }
    }
    return found
  }

  /// Every file that can open a connection or accept one.
  ///
  /// Signing fetches timestamps and revocation material; the relay,
  /// discovery, and server files serve remote card and signing
  /// service builds; the probes are debug-only; the detector runs a
  /// link-local Bonjour self-check.
  @Test
  internal func trafficCapableApiSetIsListed() throws {
    let actual = try Self.files(
      containingAny: ["URLSession", "NWConnection", "NWListener", "NWBrowser"]
    )
    let expected: Set<String> = [
      "CardCore/Sources/CardCore/RappLocalDiscovery.swift",
      "CardCore/Sources/CardCore/StreamRelayBrowser.swift",
      "CardCore/Sources/CardCore/StreamRelayListener.swift",
      "CardCore/Sources/CardCore/StreamRelayPresence.swift",
      "CardCore/Sources/CardCore/StreamRelaySession.swift",
      "Sources/App/AuthoritySchemeResolver.swift",
      "Sources/App/DebugBrowseProbe.swift",
      "Sources/App/DebugLocalNetworkProbe.swift",
      "Sources/App/LocalNetworkAccessDetector.swift",
      "Sources/App/ScsServer.swift",
      "Sources/App/SigningNetwork.swift",
      "Sources/App/SigningNetwork+AddressClassification.swift",
      "Sources/App/SigningNetwork+Destination.swift",
      "Sources/App/SigningNetwork+Redirect.swift",
      "Sources/App/SigningNetwork+Response.swift",
    ]
    #expect(
      actual == expected,
      "New network code needs a contract entry in Documentation/decisions.md first."
    )
  }

  /// A Mac never listens (decisions 2026-10-10).
  ///
  /// It is always the RAPP requester and dials the paired phone. Every
  /// place that can accept a connection is pinned here, and each one
  /// compiles away on macOS.
  @Test
  internal func macOSNeverListens() throws {
    let actual = try Self.files(
      containingAny: [
        "StreamRelayListener {", "NWListener(using", "MCNearbyServiceAdvertiser(",
      ]
    )
    let expected: Set<String> = [
      "CardCore/Sources/CardCore/MultipeerDiscoveryHelper.swift",
      "CardCore/Sources/CardCore/PersistentRelaySession.swift",
      "CardCore/Sources/CardCore/RappLocalDiscovery.swift",
      "CardCore/Sources/CardCore/StreamRelayListener.swift",
      "Sources/App/DebugListenProbe.swift",
      "Sources/App/LocalNetworkAccessDetector.swift",
      "Sources/App/PairingRelay.swift",
      "Sources/App/PhonePersistentTokenRelay+Stream.swift",
      "Sources/App/ScsServer.swift",
    ]
    #expect(
      actual == expected,
      "A new listener needs a contract entry in Documentation/decisions.md first."
    )
    let gates: [String: String] = [
      // Phone-only sources.
      "Sources/App/LocalNetworkAccessDetector.swift": "#if os(iOS)",
      "Sources/App/PhonePersistentTokenRelay+Stream.swift": "#if os(iOS)",
      // Debug probes.
      "Sources/App/DebugListenProbe.swift": "#if DEBUG",
      // The signing service starts only with FEATURE_SCS, which macOS
      // never sets, and the store sandbox grants no server side.
      "Sources/App/ScsServer.swift": "#if FEATURE_SCS",
      // The card holder's half of a pairing.
      "Sources/App/PairingRelay.swift": "#if os(iOS)\n          let made = StreamRelayListener",
      // Discovery advertises everywhere but on a Mac.
      "CardCore/Sources/CardCore/RappLocalDiscovery.swift":
        "#if !os(macOS)\n          self.startAdvertising()",
    ]
    for (file, gate) in gates {
      let text = try String(contentsOf: Self.root.appending(path: file), encoding: .utf8)
      #expect(text.contains(gate), "\(file) lost its macOS listener gate")
    }
  }

  /// Bluetooth radio code ships unwired: these files and no others
  /// may name it.
  @Test
  internal func bluetoothRadioStaysUnwired() throws {
    let actual = try Self.files(containingAny: ["BleRelay", "BleL2CAP"])
    let expected: Set<String> = [
      "CardCore/Sources/CardCore/BleL2CAPChannelHandler.swift",
      "CardCore/Sources/CardCore/BleRelayEndpoint.swift",
      "CardCore/Sources/CardCore/BleRelayEvent.swift",
      "CardCore/Sources/CardCore/BleRelayFraming.swift",
      "CardCore/Sources/CardCore/BleRelaySession.swift",
      "CardCore/Sources/CardCore/BleRelaySession+Delegate.swift",
      "CardCore/Sources/CardCore/BleRelayTransportError.swift",
    ]
    #expect(
      actual == expected,
      "Wiring Bluetooth needs a contract entry in Documentation/decisions.md first."
    )
  }

  /// The `fi.refineid.rapp.ble.v1` GATT link is driven by the DEBUG
  /// launch modes alone (decisions 2026-10-09).
  @Test
  internal func bleGattProfileStaysDebugOnly() throws {
    let actual = try Self.files(containingAny: ["RappBleGattPeripheral", "RappBleGattCentral"])
    let expected: Set<String> = [
      "CardCore/Sources/CardCore/RappBleGattCentral.swift",
      "CardCore/Sources/CardCore/RappBleGattCentral+Delegate.swift",
      "CardCore/Sources/CardCore/RappBleGattPeripheral.swift",
      "CardCore/Sources/CardCore/RappBleGattPeripheral+Delegate.swift",
      "Sources/App/DebugBlePairing.swift",
    ]
    #expect(
      actual == expected,
      "Wiring the BLE profile into the product needs a decision entry first."
    )
  }

  /// Only the two configurations that compile DEBUG sign macOS with the
  /// Bluetooth sandbox entitlement.
  @Test
  internal func bluetoothEntitlementOnlyInDebugConfigurations() throws {
    let project = try String(
      contentsOf: Self.root.appending(path: "RefineID.xcodeproj/project.pbxproj"),
      encoding: .utf8)
    let blocks = project.components(separatedBy: "isa = XCBuildConfiguration;").dropFirst()
    var granting: [String] = []
    for block in blocks where block.contains("RefineID-Debug.entitlements") {
      let tail = block.components(separatedBy: "name = ").last ?? ""
      granting.append(String(tail.prefix { character in character != ";" }))
    }
    #expect(granting.sorted() == ["Debug", "Profile"])
    let store = try String(
      contentsOf: Self.root.appending(path: "Config/RefineID-Store.entitlements"),
      encoding: .utf8)
    #expect(!store.contains("com.apple.security.device.bluetooth"))
  }

  /// ATS stays open and Bluetooth carries exactly its one purpose
  /// string in every app plist.
  @Test
  internal func applicationPlistsMatchTheContract() throws {
    for path in [
      "Config/RefineID-Info.plist",
      "Config/RefineID-Store-Info.plist",
      "Config/RefineID-iOS-Info.plist",
      "Config/RefineID-iOS-Store-Info.plist",
    ] {
      let data = try Data(contentsOf: Self.root.appending(path: path))
      let plist = try #require(
        try PropertyListSerialization.propertyList(from: data, format: nil)
          as? [String: Any]
      )
      let ats = try #require(plist["NSAppTransportSecurity"] as? [String: Any])
      #expect(ats["NSAllowsArbitraryLoads"] as? Bool == true)
      #expect(ats["NSExceptionDomains"] == nil)
      let bluetoothKeys = plist.keys.filter { $0.hasPrefix("NSBluetooth") }
      #expect(bluetoothKeys == ["NSBluetoothAlwaysUsageDescription"])
      let purpose = try #require(plist["NSBluetoothAlwaysUsageDescription"] as? String)
      #expect(!purpose.isEmpty)
    }
  }
}
