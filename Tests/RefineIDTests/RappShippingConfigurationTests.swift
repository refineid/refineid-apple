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

  @Test("RAPP extension is a distinct embedded product on every platform")
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

  @Test("Shipping configurations carry the full version with the remote card")
  internal func shippingConfigurationsCarryRemoteCard() throws {
    // Owner decision 2026-09-10: the first full version ships the
    // remote card in every configuration. The RAPP extension is no
    // longer excluded from any embed phase, and every configuration
    // points at the development Info.plists and entitlements that
    // carry the local-network declarations and the relay listener.
    // The store files stay in the repository as the retired gated
    // reference; nothing points at them.
    let project = try String(
      contentsOf: Self.root.appending(path: "RefineID.xcodeproj/project.pbxproj"),
      encoding: .utf8)
    func occurrences(of needle: String) -> Int {
      project.components(separatedBy: needle).count - 1
    }
    #expect(occurrences(of: "RefineIDRappTokenExtension.appex,") == 0)
    #expect(
      occurrences(
        of: "INFOPLIST_FILE = \"Config/RefineID-iOS-Store-Info.plist\";") == 0)
    #expect(
      occurrences(
        of: "INFOPLIST_FILE = \"Config/RefineID-iOS-Info.plist\";") == 4)

    // The macOS shape mirrors the iOS one: all four configurations
    // point the Mac app at the development Info.plist and
    // entitlements with the remote card's declarations.
    #expect(
      occurrences(
        of: "\"INFOPLIST_FILE[sdk=macosx*]\" = \"Config/RefineID-Store-Info.plist\";") == 0)
    #expect(
      occurrences(
        of: "\"INFOPLIST_FILE[sdk=macosx*]\" = \"Config/RefineID-Info.plist\";") == 4)
    #expect(
      occurrences(
        of: "\"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]\" = \"Config/RefineID-Store.entitlements\";")
        == 0)
    #expect(
      occurrences(
        of: "\"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]\" = Config/RefineID.entitlements;") == 4)

    let features = try String(
      contentsOf: Self.root.appending(path: "Config/Features.xcconfig"),
      encoding: .utf8)
    #expect(features.contains("REFINEID_REMOTE_CARD_FEATURE = REFINEID_REMOTE_CARD"))
    #expect(
      features.contains("REFINEID_REMOTE_CARD_FEATURE[config=TestFlight] = REFINEID_REMOTE_CARD"))
    #expect(
      features.contains("REFINEID_REMOTE_CARD_FEATURE[config=Release] = REFINEID_REMOTE_CARD"))

    // Activation is enabled across configurations.
    #expect(features.contains("REFINEID_ACTIVATION_FEATURE = FEATURE_CARD_ACTIVATION"))
    #expect(
      features.contains("REFINEID_ACTIVATION_FEATURE[config=TestFlight] = FEATURE_CARD_ACTIVATION"))
    #expect(
      features.contains("REFINEID_ACTIVATION_FEATURE[config=Release] = FEATURE_CARD_ACTIVATION"))

    // The full version enables contactless reading, the visible PDF
    // stamp, and the SCS loopback server in every configuration.
    #expect(
      features.contains(
        "REFINEID_FEATURES = FEATURE_PDF_STAMP FEATURE_CONTACTLESS FEATURE_SCS"))
  }

  @Test("Retired store files are referenced by no build configuration")
  internal func retiredStoreFilesAreUnreferenced() throws {
    // Owner decision 2026-09-10: the `Config/*-Store-*` files are the
    // retired gated reference; every configuration ships the development
    // files. This test fails if any configuration is pointed back at
    // them, so the gates cannot silently return. It replaces the retired
    // store-vs-development shape comparisons, which compared files no
    // configuration consumes and which were already red on main from
    // document-type drift (`CFBundleDocumentTypes`,
    // `UTImportedTypeDeclarations`).
    let project = try String(
      contentsOf: Self.root.appending(path: "RefineID.xcodeproj/project.pbxproj"),
      encoding: .utf8)
    func assignments(of path: String) -> Int {
      project.components(separatedBy: "= \"\(path)\";").count - 1
        + project.components(separatedBy: "= \(path);").count - 1
    }
    #expect(assignments(of: "Config/RefineID-iOS-Store-Info.plist") == 0)
    #expect(assignments(of: "Config/RefineID-Store-Info.plist") == 0)
    #expect(assignments(of: "Config/RefineID-Store.entitlements") == 0)
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
    // Both candidates carry the remote card: the RAPP extension, the
    // local-network declarations, and on macOS the server entitlement.
    #expect(source.components(separatedBy: "hasRapp: true").count - 1 == 2)
    #expect(source.contains("NSBonjourServices present without the remote card"))
    #expect(source.contains("network.server entitlement present without the remote card"))
    #expect(source.contains("iPhone-only artifact requiring iOS 26.0 and an NFC antenna"))
  }
}
