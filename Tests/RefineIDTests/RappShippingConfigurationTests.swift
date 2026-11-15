// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

@Suite("RAPP shipping configuration")
internal struct RappShippingConfigurationTests {
  // MARK: Static Properties

  private enum ConfigurationError: Error {
    case missingExtensionAttributes
  }

  private static let classID = "fi.refineid.ReFineID.rapp-token"
  private static let service = "_refineid-stream._tcp"
  private static let testHostConfigurationCount = 4

  // MARK: Static Computed Properties

  private static var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  // MARK: Static Functions

  private static func plist(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: root.appending(path: path))
    return try #require(
      PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any])
  }

  private static func extensionAttributes(
    _ plist: [String: Any]
  ) throws -> [String: Any] {
    guard
      let attributes = (plist["NSExtension"] as? [String: Any])?["NSExtensionAttributes"]
        as? [String: Any]
    else {
      throw ConfigurationError.missingExtensionAttributes
    }
    return attributes
  }

  // MARK: Functions

  @Test("RAPP and smart-card drivers have separate CryptoTokenKit classes")
  internal func separateTokenDrivers() throws {
    #expect(PersistentTokenIdentity.classID == Self.classID)

    let reader = try Self.plist("Config/TokenExtension-Info.plist")
    let rapp = try Self.plist("Config/RappTokenExtension-Info.plist")
    let readerAttributes = try Self.extensionAttributes(reader)
    let rappAttributes = try Self.extensionAttributes(rapp)
    #expect(readerAttributes["com.apple.ctk.class-id"] as? String == "fi.refineid.ReFineID.token")
    #expect(
      readerAttributes["com.apple.ctk.driver-class"] as? String
        == "RefineIDTokenExtension.TokenDriver")
    #expect(readerAttributes["com.apple.ctk.token-type"] as? String == "smartcard")
    #expect(rappAttributes["com.apple.ctk.class-id"] as? String == Self.classID)
    #expect(
      rappAttributes["com.apple.ctk.driver-class"] as? String
        == "$(PRODUCT_MODULE_NAME).PersistentTokenDriver")
    #expect(rappAttributes["com.apple.ctk.token-type"] == nil)
  }

  @Test("RAPP extension is a distinct embedded product on iOS only")
  internal func separateRappExtensionTarget() throws {
    let project = try String(
      contentsOf: Self.root.appending(path: "RefineID.xcodeproj/project.pbxproj"),
      encoding: .utf8)
    #expect(project.contains("RefineIDRappTokenExtension"))
    #expect(project.contains(Self.classID))
    #expect(project.contains("RappTokenExtension"))
    #expect(project.contains("Config/RappTokenExtension-iOS.entitlements"))
    // The macOS MVP gates the remote card off (decisions 2026-11-14),
    // so macOS embeds no RAPP extension; the filter below is what
    // keeps it out of the Mac archive.
    let embed = try #require(
      project.split(whereSeparator: \.isNewline).first { line in
        line.contains("RefineIDRappTokenExtension.appex in Embed Foundation Extensions")
      })
    #expect(embed.contains("platformFilter = ios"))
    #expect(!project.contains("RefineIDRappTokenExtension.appex */; platformFilters"))
  }

  @Test("macOS carries the local card and excludes RAPP and SCS")
  internal func macOSShipsTheLocalCardOnly() throws {
    let project = try String(
      contentsOf: Self.root.appending(path: "RefineID.xcodeproj/project.pbxproj"),
      encoding: .utf8)
    #expect(
      project.components(
        separatedBy:
          "\"INFOPLIST_FILE[sdk=macosx*]\" = \"Config/RefineID-Store-Info.plist\";"
      ).count - 1 == 4)
    // Every configuration signs macOS with the store entitlements
    // (decisions 2026-11-08); with the remote card gated off for the
    // MVP those grant no Bluetooth (decisions 2026-11-14).
    #expect(
      project.components(
        separatedBy:
          "\"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]\" = \"Config/RefineID-Store.entitlements\";"
      ).count - 1 == 4)
    #expect(!project.contains("RefineID-Debug.entitlements"))
    let store = try Self.plist("Config/RefineID-Store.entitlements")
    #expect(store["com.apple.security.device.bluetooth"] == nil)
    #expect(store["com.apple.security.network.client"] as? Bool == true)
    #expect(store["com.apple.security.network.server"] == nil)
    let features = try String(
      contentsOf: Self.root.appending(path: "Config/Features.xcconfig"), encoding: .utf8)
    #expect(
      features.contains(
        "REFINEID_FEATURES = FEATURE_CONTACTLESS FEATURE_TIMESTAMP_CONFIG FEATURE_PDF_STAMP\n"))
    #expect(!features.contains("REFINEID_FEATURES[sdk="))
    #expect(features.contains("REFINEID_REMOTE_CARD_FEATURE = REFINEID_REMOTE_CARD\n"))
    #expect(
      features.contains(
        "REFINEID_REMOTE_CARD_FEATURE[config=TestFlight] = REFINEID_REMOTE_CARD\n"))
    #expect(
      features.contains(
        "REFINEID_REMOTE_CARD_FEATURE[config=Release] = REFINEID_REMOTE_CARD\n"))
    #expect(features.contains("REFINEID_REMOTE_CARD_FEATURE[sdk=macosx*] =\n"))
    #expect(features.contains("REFINEID_REMOTE_CARD_FEATURE[sdk=macosx*,config=TestFlight] =\n"))
    #expect(features.contains("REFINEID_REMOTE_CARD_FEATURE[sdk=macosx*,config=Release] =\n"))
    #expect(features.contains("REFINEID_ACTIVATION_FEATURE = FEATURE_CARD_ACTIVATION"))
  }

  @Test("macOS declares no remote-card services or permission prompts")
  internal func macOSDeclaresNoRemoteCardServices() throws {
    let full = try Self.plist("Config/RefineID-Info.plist")
    let store = try Self.plist("Config/RefineID-Store-Info.plist")
    for (name, plist) in [
      ("Config/RefineID-Info.plist", full),
      ("Config/RefineID-Store-Info.plist", store),
    ] {
      #expect(plist["NSBonjourServices"] == nil, "\(name)")
      #expect(plist["NSLocalNetworkUsageDescription"] == nil, "\(name)")
      #expect(plist["NSBluetoothAlwaysUsageDescription"] == nil, "\(name)")
    }
    #expect(
      try JSONSerialization.data(withJSONObject: full, options: .sortedKeys)
        == JSONSerialization.data(withJSONObject: store, options: .sortedKeys))
  }

  @Test("RAPP network declarations are present in shipping containers")
  internal func networkDeclarations() throws {
    for path in [
      "Config/RefineID-iOS-Info.plist",
      "Config/RappTokenExtension-Info.plist",
    ] {
      let plist = try Self.plist(path)
      #expect(plist["NSLocalNetworkUsageDescription"] is String)
      let services = try #require(plist["NSBonjourServices"] as? [String])
      #expect(services.contains(Self.service))
    }

    let rappIOS = try Self.plist("Config/RappTokenExtension-iOS.entitlements")
    #expect(rappIOS["keychain-access-groups"] is [Any])
    #expect(rappIOS["com.apple.security.smartcard"] == nil)
    #expect(rappIOS["com.apple.security.network.client"] == nil)

    // The shipping Mac keeps outbound network access for timestamps and
    // revocation checks, and nothing listens. The macOS RAPP extension
    // entitlements stay a client-only file for its target's macOS build;
    // the MVP embeds no such extension.
    for path in [
      "Config/RefineID-Store.entitlements",
      "Config/RappTokenExtension.entitlements",
    ] {
      let entitlements = try Self.plist(path)
      #expect(entitlements["com.apple.security.network.client"] as? Bool == true, "\(path)")
      #expect(entitlements["com.apple.security.network.server"] == nil, "\(path)")
    }

    let reader = try Self.plist("Config/TokenExtension.entitlements")
    #expect(reader["com.apple.security.smartcard"] as? Bool == true)
    #expect(reader["com.apple.security.network.client"] == nil)
    #expect(reader["com.apple.security.network.server"] == nil)

    let rapp = try Self.plist("Config/RappTokenExtension.entitlements")
    #expect(rapp["com.apple.security.smartcard"] == nil)
    #expect(rapp["keychain-access-groups"] is [Any])
  }

  @Test("Release inspection enforces the separate RAPP archive topology")
  internal func releaseInspectionTopology() throws {
    let source = try String(
      contentsOf: Self.root.appending(
        path: "Scripts/apple-app-store-connect-release-manager.swift"),
      encoding: .utf8)
    #expect(source.contains("RefineIDRappTokenExtension.appex"))
    #expect(source.contains("fi.refineid.ReFineID.rapp-token"))
    #expect(source.contains("RAPP and direct-reader entitlements are separated"))
    #expect(!source.contains("network entitlements match the gated-relay shape"))
    // Only the iOS archive carries the remote card; the macOS layout
    // gates it off (decisions 2026-11-14).
    #expect(source.components(separatedBy: "hasRapp: true").count - 1 == 1)
    #expect(source.components(separatedBy: "hasRapp: false").count - 1 == 1)
    #expect(source.contains("network.server entitlement; a Mac never listens"))
    #expect(source.contains("NSBonjourServices present without the remote card"))
    #expect(source.contains("NSBluetoothAlwaysUsageDescription present without the remote card"))
    #expect(source.contains("network.server entitlement present without the remote card"))
    #expect(source.contains("bluetooth entitlement present without the remote card"))
    #expect(source.contains("CoreBluetooth linked without the remote card"))
    #expect(source.contains("iPhone-only artifact requiring iOS 26.0 and an NFC antenna"))
  }

  @Test("Test host listens on loopback and shares no state")
  internal func testHostListensWithoutSharedState() throws {
    let host = try Self.plist("Config/RefineIDTestHost.entitlements")
    #expect(host["com.apple.security.network.server"] as? Bool == true)
    #expect(host["com.apple.security.application-groups"] == nil)
    #expect(host["keychain-access-groups"] == nil)
    let project = try String(
      contentsOf: Self.root.appending(path: "RefineID.xcodeproj/project.pbxproj"),
      encoding: .utf8)
    #expect(
      project.components(
        separatedBy: "CODE_SIGN_ENTITLEMENTS = Config/RefineIDTestHost.entitlements;"
      ).count - 1 == Self.testHostConfigurationCount)
  }
}
