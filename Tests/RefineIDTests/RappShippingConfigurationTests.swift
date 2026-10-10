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
  private static let service = "_refineid-rly._tcp"

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

  @Test("RAPP extension is a distinct iOS embedded product")
  internal func separateRappExtensionTarget() throws {
    let project = try String(
      contentsOf: Self.root.appending(path: "RefineID.xcodeproj/project.pbxproj"),
      encoding: .utf8)
    #expect(project.contains("RefineIDRappTokenExtension"))
    #expect(project.contains(Self.classID))
    #expect(project.contains("RappTokenExtension"))
    #expect(project.contains("Config/RappTokenExtension-iOS.entitlements"))
    #expect(!project.contains("RefineIDRappTokenExtension.appex */; platformFilters"))
  }

  @Test("macOS configurations exclude remote services while iOS retains them")
  internal func shippingConfigurationsGateRemoteCard() throws {
    let project = try String(
      contentsOf: Self.root.appending(path: "RefineID.xcodeproj/project.pbxproj"),
      encoding: .utf8)
    #expect(project.contains("RefineIDRappTokenExtension.appex */; platformFilter = ios;"))
    #expect(
      project.components(
        separatedBy:
          "\"INFOPLIST_FILE[sdk=macosx*]\" = \"Config/RefineID-Store-Info.plist\";"
      ).count - 1 == 4)
    // Release and TestFlight sign macOS with the store entitlements; Debug
    // and Profile add only Bluetooth to them (decisions 2026-10-09).
    #expect(
      project.components(
        separatedBy:
          "\"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]\" = \"Config/RefineID-Store.entitlements\";"
      ).count - 1 == 2)
    #expect(
      project.components(
        separatedBy:
          "\"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]\" = \"Config/RefineID-Debug.entitlements\";"
      ).count - 1 == 2)
    let store = try Self.plist("Config/RefineID-Store.entitlements")
    var development = try Self.plist("Config/RefineID-Debug.entitlements")
    #expect(development.removeValue(forKey: "com.apple.security.device.bluetooth") as? Bool == true)
    #expect(Set(development.keys) == Set(store.keys))
    for (key, value) in store {
      #expect(String(describing: value) == String(describing: development[key] ?? ""), "\(key)")
    }
    let features = try String(
      contentsOf: Self.root.appending(path: "Config/Features.xcconfig"), encoding: .utf8)
    #expect(features.contains("REFINEID_FEATURES[sdk=macosx*] = FEATURE_CONTACTLESS\n"))
    #expect(features.contains("REFINEID_REMOTE_CARD_FEATURE[sdk=macosx*] =\n"))
    #expect(features.contains("REFINEID_REMOTE_CARD_FEATURE = REFINEID_REMOTE_CARD"))
    #expect(features.contains("REFINEID_ACTIVATION_FEATURE = FEATURE_CARD_ACTIVATION"))
  }

  @Test("macOS store declarations preserve local features without remote networking")
  internal func localStoreDeclarations() throws {
    var full = try Self.plist("Config/RefineID-Info.plist")
    full.removeValue(forKey: "NSBonjourServices")
    full.removeValue(forKey: "NSLocalNetworkUsageDescription")
    let store = try Self.plist("Config/RefineID-Store-Info.plist")
    #expect(
      try JSONSerialization.data(withJSONObject: full, options: .sortedKeys)
        == JSONSerialization.data(withJSONObject: store, options: .sortedKeys))
    var entitlements = try Self.plist("Config/RefineID.entitlements")
    entitlements.removeValue(forKey: "com.apple.security.network.server")
    let storeEntitlements = try Self.plist("Config/RefineID-Store.entitlements")
    #expect(
      try JSONSerialization.data(withJSONObject: entitlements, options: .sortedKeys)
        == JSONSerialization.data(withJSONObject: storeEntitlements, options: .sortedKeys))
  }

  @Test("RAPP network declarations are present in shipping containers")
  internal func networkDeclarations() throws {
    for path in [
      "Config/RefineID-Info.plist",
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

    for path in ["Config/RefineID.entitlements", "Config/RappTokenExtension.entitlements"] {
      let entitlements = try Self.plist(path)
      #expect(entitlements["com.apple.security.network.client"] as? Bool == true)
      #expect(entitlements["com.apple.security.network.server"] as? Bool == true)
    }

    let reader = try Self.plist("Config/TokenExtension.entitlements")
    #expect(reader["com.apple.security.smartcard"] as? Bool == true)
    #expect(reader["com.apple.security.network.client"] == nil)
    #expect(reader["com.apple.security.network.server"] == nil)

    let rapp = try Self.plist("Config/RappTokenExtension.entitlements")
    #expect(rapp["com.apple.security.smartcard"] == nil)
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
    #expect(source.components(separatedBy: "hasRapp: true").count - 1 == 1)
    #expect(source.components(separatedBy: "hasRapp: false").count - 1 == 1)
    #expect(source.contains("NSBonjourServices present without the remote card"))
    #expect(source.contains("network.server entitlement present without the remote card"))
    #expect(source.contains("iPhone-only artifact requiring iOS 26.0 and an NFC antenna"))
  }
}
