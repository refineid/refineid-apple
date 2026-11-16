// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@Suite("App Store Connect release manager")
internal struct AppleAppStoreConnectReleaseManagerTests {
  // MARK: Static Computed Properties

  private static var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private static var managerPath: String {
    "Scripts/apple-app-store-connect-release-manager.swift"
  }

  private static var managerTestsPath: String {
    "Scripts/TestAppleAppStoreConnectReleaseManager.swift"
  }

  // MARK: Static Functions

  private static func text(_ path: String) throws -> String {
    try String(contentsOf: root.appending(path: path), encoding: .utf8)
  }

  private static func managerSource() throws -> String {
    try text(managerPath)
  }

  // MARK: Functions

  @Test("Environment, JWT minting, and HTTP requests share one App Store Connect stack")
  internal func singleAppStoreConnectStack() throws {
    let source = try Self.managerSource()
    #expect(source.components(separatedBy: "func releaseEnvironment()").count - 1 == 1)
    #expect(
      source.components(separatedBy: "P256.Signing.PrivateKey(pemRepresentation:").count - 1 == 1)
    #expect(source.components(separatedBy: "func apiResponse(").count - 1 == 1)
    #expect(source.components(separatedBy: "func api(").count - 1 == 1)
    #expect(source.contains("ASC_PRIVATE_KEY_PATH"))
    #expect(source.contains("callerEnvironment[key] == nil"))
    #expect(source.contains("cachedAPIToken"))
    #expect(!source.contains("func loadEnvironment("))
    #expect(!source.contains("let token: String ="))
    #expect(!source.contains("func releaseAPI("))
  }

  @Test("Repository root, error exits, and retired Cargo helper have no duplicates")
  internal func noDuplicateHelpersOrDeadCargoCode() throws {
    let source = try Self.managerSource()
    #expect(source.components(separatedBy: "let releaseRepositoryRoot =").count - 1 == 1)
    #expect(source.components(separatedBy: "func releaseFail(").count - 1 == 1)
    #expect(!source.contains("rappCargoTargetDirectory"))
    #expect(!source.contains("let repository ="))
    #expect(!source.contains("func die("))
  }

  @Test("The lint and PR gates cover the release manager tests")
  internal func gatesCoverReleaseManagerTests() throws {
    let lint = try Self.text("Scripts/lint.sh")
    #expect(
      lint.contains(
        #"typecheck "release manager" Scripts/apple-app-store-connect-release-manager.swift"#
      ))
    #expect(
      lint.contains(
        #"typecheck "release manager tests" Scripts/TestAppleAppStoreConnectReleaseManager.swift"#
      ))
    let formatPaths = try #require(
      lint.components(separatedBy: "format_paths=(").last?
        .components(separatedBy: ")").first)
    #expect(!formatPaths.contains(Self.managerPath))
    #expect(!formatPaths.contains(Self.managerTestsPath))

    let gate = try Self.text("Scripts/test.sh")
    #expect(gate.contains("swift \(Self.managerTestsPath)"))
  }
}
