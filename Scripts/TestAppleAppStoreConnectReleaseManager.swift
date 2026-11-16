#!/usr/bin/env swift
// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// Usage: swift Scripts/TestAppleAppStoreConnectReleaseManager.swift
//
// Checks the App Store Connect release manager's command line, environment
// loading, credential precedence, private-key validation, and URL host checks
// without reading real credentials or touching the network. The script is
// compiled once into a temporary directory and every case runs against its own
// isolated HOME directory.
//
// The shebang keeps its own line and a blank line follows it: swift-format
// joins a comment placed directly under the shebang onto the shebang line.

import Foundation

private let repositoryRoot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()

private let managerPath = "Scripts/apple-app-store-connect-release-manager.swift"
private let successExitStatus: Int32 = 0
private let rejectedExitStatus: Int32 = 1

private struct CommandResult {
  let status: Int32
  let output: String
}

private struct CommandCase {
  let name: String
  let arguments: [String]
  let envFile: String?
  let extraEnvironment: [String: String]
  let files: [String: String]
  let expectedStatus: Int32
  let expectedOutput: (URL) -> String
}

private func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("ERROR: \(message)\n".utf8))
  exit(1)
}

private func run(
  _ executable: String,
  _ arguments: [String],
  directory: URL,
  environment: [String: String]? = nil
) -> CommandResult {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.currentDirectoryURL = directory
  process.standardInput = FileHandle.nullDevice
  if let environment {
    process.environment = environment
  }

  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = pipe

  do {
    try process.run()
  } catch {
    fail("could not start \(executable): \(error.localizedDescription)")
  }

  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()

  return CommandResult(
    status: process.terminationStatus,
    output: String(bytes: data, encoding: .utf8) ?? ""
  )
}

private func compileManager(into directory: URL) -> URL {
  let manager = repositoryRoot.appendingPathComponent(managerPath)
  let binary = directory.appendingPathComponent("apple-app-store-connect-release-manager")
  let result = run(
    "/usr/bin/xcrun",
    ["swiftc", manager.path, "-o", binary.path],
    directory: directory
  )
  if result.status != 0 {
    fail("could not compile \(managerPath):\n\(result.output)")
  }
  return binary
}

private func isolatedEnvironment(home: URL, overrides: [String: String]) -> [String: String] {
  var environment = ProcessInfo.processInfo.environment
  environment.removeValue(forKey: "ASC_KEY_ID")
  environment.removeValue(forKey: "ASC_ISSUER_ID")
  environment.removeValue(forKey: "ASC_PRIVATE_KEY_PATH")
  environment["HOME"] = home.path
  for (key, value) in overrides {
    environment[key] = value
  }
  return environment
}

private func commandCases() -> [CommandCase] {
  [
    CommandCase(
      name: "help runs without credentials",
      arguments: ["--help"],
      envFile: nil,
      extraEnvironment: [:],
      files: [:],
      expectedStatus: successExitStatus,
      expectedOutput: { _ in
        "Usage: Scripts/apple-app-store-connect-release-manager.swift <command> [arguments]"
      }
    ),
    CommandCase(
      name: "stamp dry-run runs without credentials",
      arguments: ["stamp", "--dry-run"],
      envFile: nil,
      extraEnvironment: [:],
      files: [:],
      expectedStatus: successExitStatus,
      expectedOutput: { _ in "would stamp " }
    ),
    CommandCase(
      name: "unknown command fails cleanly without credentials",
      arguments: ["--not-a-command"],
      envFile: nil,
      extraEnvironment: [:],
      files: [:],
      expectedStatus: rejectedExitStatus,
      expectedOutput: { _ in "FAIL: unknown command or wrong arguments: '--not-a-command'" }
    ),
    CommandCase(
      name: "unknown candidate flag fails cleanly",
      arguments: ["candidate", "--not-a-flag"],
      envFile: nil,
      extraEnvironment: [:],
      files: [:],
      expectedStatus: rejectedExitStatus,
      expectedOutput: { _ in "FAIL: unknown candidate argument: --not-a-flag" }
    ),
    CommandCase(
      name: "invalid JSON body fails before credentials",
      arguments: ["api", "POST", "/v1/apps", "not-json"],
      envFile: nil,
      extraEnvironment: [:],
      files: [:],
      expectedStatus: rejectedExitStatus,
      expectedOutput: { _ in "FAIL: the body is not a JSON object" }
    ),
    CommandCase(
      name: "relative API path is rejected before credentials",
      arguments: ["api", "GET", "v1/apps"],
      envFile: nil,
      extraEnvironment: [:],
      files: [:],
      expectedStatus: rejectedExitStatus,
      expectedOutput: { _ in "FAIL: bad path: v1/apps" }
    ),
    CommandCase(
      name: "foreign host URL is rejected before credentials",
      arguments: ["get", "https://example.com/v1/apps"],
      envFile: nil,
      extraEnvironment: [:],
      files: [:],
      expectedStatus: rejectedExitStatus,
      expectedOutput: { _ in "FAIL: bad path: https://example.com/v1/apps" }
    ),
    CommandCase(
      name: "store command reports missing ASC_KEY_ID",
      arguments: ["app-id"],
      envFile: nil,
      extraEnvironment: [:],
      files: [:],
      expectedStatus: rejectedExitStatus,
      expectedOutput: { _ in "FAIL: ASC_KEY_ID is not set" }
    ),
    CommandCase(
      name: "env file loads export and quoted values",
      arguments: ["app-id"],
      envFile: """
        # App Store Connect credentials
        export ASC_KEY_ID="FILE_KEY"
        """,
      extraEnvironment: [:],
      files: [:],
      expectedStatus: rejectedExitStatus,
      expectedOutput: { _ in "FAIL: ASC_ISSUER_ID is not set" }
    ),
    CommandCase(
      name: "env file expands leading tilde in ASC_PRIVATE_KEY_PATH",
      arguments: ["app-id"],
      envFile: """
        ASC_KEY_ID="FILE_KEY"
        ASC_ISSUER_ID='FILE_ISSUER'
        ASC_PRIVATE_KEY_PATH="~/keys/custom.p8"
        """,
      extraEnvironment: [:],
      files: [:],
      expectedStatus: rejectedExitStatus,
      expectedOutput: { home in
        "FAIL: no key at \(home.appendingPathComponent("keys/custom.p8").path)"
      }
    ),
    CommandCase(
      name: "env file expands $HOME in ASC_PRIVATE_KEY_PATH",
      arguments: ["app-id"],
      envFile: """
        export ASC_KEY_ID=FILE_KEY
        export ASC_ISSUER_ID=FILE_ISSUER
        export ASC_PRIVATE_KEY_PATH='$HOME/keys/dollar.p8'
        """,
      extraEnvironment: [:],
      files: [:],
      expectedStatus: rejectedExitStatus,
      expectedOutput: { home in
        "FAIL: no key at \(home.appendingPathComponent("keys/dollar.p8").path)"
      }
    ),
    CommandCase(
      name: "caller environment overrides env file values",
      arguments: ["app-id"],
      envFile: """
        ASC_KEY_ID="FILE_KEY"
        ASC_ISSUER_ID="FILE_ISSUER"
        """,
      extraEnvironment: ["ASC_KEY_ID": "CALLER_KEY"],
      files: [:],
      expectedStatus: rejectedExitStatus,
      expectedOutput: { home in
        let expectedKey =
          home
          .appendingPathComponent(".appstoreconnect/private_keys/AuthKey_CALLER_KEY.p8")
          .path
        return "FAIL: no key at \(expectedKey)"
      }
    ),
    CommandCase(
      name: "malformed .p8 key fails before network call",
      arguments: ["app-id"],
      envFile: """
        ASC_KEY_ID="FILE_KEY"
        ASC_ISSUER_ID="FILE_ISSUER"
        ASC_PRIVATE_KEY_PATH="~/keys/bad.p8"
        """,
      extraEnvironment: [:],
      files: ["keys/bad.p8": "not-a-p256-key\n"],
      expectedStatus: rejectedExitStatus,
      expectedOutput: { home in
        let badKey = home.appendingPathComponent("keys/bad.p8").path
        return "FAIL: the .p8 at \(badKey) is not a readable P-256 key"
      }
    ),
  ]
}

private func main() {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("asc-release-manager-tests-\(UUID().uuidString)")
  do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  } catch {
    fail("could not create \(directory.path): \(error.localizedDescription)")
  }
  defer { try? FileManager.default.removeItem(at: directory) }

  let binary = compileManager(into: directory)
  let cases = commandCases()
  var failures = 0

  for (index, commandCase) in cases.enumerated() {
    let home = directory.appendingPathComponent("home-\(index)", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
      if let envFile = commandCase.envFile {
        let envDirectory = home.appendingPathComponent(".appstoreconnect", isDirectory: true)
        try FileManager.default.createDirectory(
          at: envDirectory, withIntermediateDirectories: true)
        try envFile.write(
          to: envDirectory.appendingPathComponent("env"),
          atomically: true,
          encoding: .utf8
        )
      }
      for (relativePath, contents) in commandCase.files {
        let fileURL = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
          at: fileURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
      }
    } catch {
      fail("could not stage \(commandCase.name): \(error.localizedDescription)")
    }

    let expected = commandCase.expectedOutput(home)
    let result = run(
      binary.path,
      commandCase.arguments,
      directory: repositoryRoot,
      environment: isolatedEnvironment(home: home, overrides: commandCase.extraEnvironment)
    )
    let matched = result.status == commandCase.expectedStatus && result.output.contains(expected)
    guard matched else {
      failures += 1
      FileHandle.standardError.write(
        Data(
          "FAIL: \(commandCase.name) \(commandCase.arguments): exit \(result.status), expected '\(expected)', output:\n\(result.output)\n"
            .utf8
        )
      )
      continue
    }
    print("ok: \(commandCase.name)")
  }

  if failures > 0 {
    fail("\(failures) of \(cases.count) release-manager cases failed")
  }

  print("ok: \(cases.count) release-manager cases")
}

main()
