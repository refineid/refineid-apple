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

  // The gate scripts are host tooling, and Process does not exist on iOS, so
  // the plan checks compile for macOS only.
  #if os(macOS)
    /// Asks a gate script what it will do and returns the answer.
    ///
    /// Both plan modes run no step, so this checks a gate's resolved plan
    /// rather than the text of the script that builds it.
    private static func gatePlan(_ script: String, _ arguments: String...) throws -> String {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/bash")
      process.arguments = [script] + arguments
      process.currentDirectoryURL = root
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = pipe
      try process.run()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let answer = try #require(String(bytes: data, encoding: .utf8))
      process.waitUntilExit()
      #expect(
        process.terminationStatus == 0,
        "\(script) \(arguments.joined(separator: " ")) exited \(process.terminationStatus):\n\(answer)"
      )
      return answer
    }
  #endif

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

  #if os(macOS)
    @Test("The lint and PR gates cover the release manager tests")
    internal func gatesCoverReleaseManagerTests() throws {
      let lint = try Self.gatePlan("Scripts/lint.sh", "list")
      #expect(lint.contains("typecheck \(Self.managerPath)"))
      #expect(lint.contains("typecheck \(Self.managerTestsPath)"))
      #expect(!lint.contains("format \(Self.managerPath)"))
      #expect(!lint.contains("format \(Self.managerTestsPath)"))

      let gate = try Self.gatePlan("Scripts/test.sh", "plan", "pr")
      #expect(gate.contains("swift \(Self.managerTestsPath)"))
    }
  #endif
}
