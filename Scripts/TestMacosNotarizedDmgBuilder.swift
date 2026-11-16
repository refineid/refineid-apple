#!/usr/bin/env swift
// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// Usage: swift Scripts/TestMacosNotarizedDmgBuilder.swift
//
// Checks the direct-download DMG builder's command line. Unknown options,
// missing values, an unsupported configuration, an empty app name and an empty
// notarization profile must each stop the run with a clear message before any
// build, signing, keychain or network work. The builder is compiled once into
// a temporary directory and every case runs that binary.
//
// The shebang keeps its own line and a blank line follows it: swift-format
// joins a comment placed directly under the shebang onto the shebang line.

import Foundation

private let repositoryRoot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()

private let builderPath = "Scripts/macos-notarized-dmg-builder.swift"
private let rejectedExitStatus: Int32 = 1

private struct CommandResult {
  let status: Int32
  let output: String
}

private struct RejectionCase {
  let name: String
  let arguments: [String]
  let expected: String
}

private func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("ERROR: \(message)\n".utf8))
  exit(1)
}

private func run(_ executable: String, _ arguments: [String], directory: URL) -> CommandResult {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.currentDirectoryURL = directory
  process.standardInput = FileHandle.nullDevice

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
    output: String(decoding: data, as: UTF8.self)
  )
}

private func compileBuilder(into directory: URL) -> URL {
  let builder = repositoryRoot.appendingPathComponent(builderPath)
  let binary = directory.appendingPathComponent("macos-notarized-dmg-builder")
  let result = run(
    "/usr/bin/xcrun",
    ["swiftc", builder.path, "-o", binary.path],
    directory: directory
  )
  if result.status != 0 {
    fail("could not compile \(builderPath):\n\(result.output)")
  }
  return binary
}

private func rejectionCases() -> [RejectionCase] {
  [
    RejectionCase(
      name: "unknown option",
      arguments: ["--not-a-flag"],
      expected: "unknown option: --not-a-flag"
    ),
    RejectionCase(
      name: "missing option value",
      arguments: ["--notary-profile"],
      expected: "missing value for --notary-profile"
    ),
    RejectionCase(
      name: "unsupported configuration",
      arguments: ["--configuration", "Beta"],
      expected: "unsupported configuration: Beta"
    ),
    RejectionCase(
      name: "empty app name",
      arguments: ["--app-name", ""],
      expected: "--app-name is required"
    ),
    RejectionCase(
      name: "empty notary profile",
      arguments: ["--notary-profile", ""],
      expected: "no notarization credential"
    ),
    // The flags must parse without being reported as unknown before the
    // credential check stops the run.
    RejectionCase(
      name: "rebuild and overwrite flags parse",
      arguments: ["--force-rebuild", "--overwrite", "--notary-profile", ""],
      expected: "no notarization credential"
    ),
  ]
}

private func main() {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("macos-notarized-dmg-builder-tests-\(UUID().uuidString)")
  do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  } catch {
    fail("could not create \(directory.path): \(error.localizedDescription)")
  }
  defer { try? FileManager.default.removeItem(at: directory) }

  let binary = compileBuilder(into: directory)
  let cases = rejectionCases()
  var failures = 0

  for rejectionCase in cases {
    let result = run(binary.path, rejectionCase.arguments, directory: repositoryRoot)
    let rejected =
      result.status == rejectedExitStatus && result.output.contains(rejectionCase.expected)
    guard rejected else {
      failures += 1
      FileHandle.standardError.write(
        Data(
          "FAIL: \(rejectionCase.name) \(rejectionCase.arguments): exit \(result.status), output:\n\(result.output)\n"
            .utf8
        )
      )
      continue
    }
    print("ok: \(rejectionCase.name)")
  }

  if failures > 0 {
    fail("\(failures) of \(cases.count) command-line cases failed")
  }

  print("ok: \(cases.count) command-line cases")
}

main()
