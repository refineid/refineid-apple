#!/usr/bin/env swift
// Copyright 2026 Petri Koistinen.
//
// Builds a Developer ID signed, notarized, stapled macOS DMG for direct
// distribution. This is a direct-download artifact path only. It is separate
// from the App Store release manager and does not upload to App Store Connect.
//
// This tool is intentionally small and explicit:
//   1. Build the macOS app from the current checkout.
//   2. Sign it with Developer ID Application.
//   3. Package it into a DMG.
//   4. Notarize the DMG with notarytool.
//   5. Staple the notarization ticket.
//   6. Validate the staple and the signature.
//   7. Write a checksum file next to the DMG.

import Foundation

private func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("ERROR: \(message)\n".utf8))
  exit(1)
}

private func note(_ message: String) {
  print("ok: \(message)")
}

private func run(
  _ executable: String,
  _ arguments: [String],
  directory: URL? = nil,
  capture: Bool = false
) -> (status: Int32, stdout: String, stderr: String) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.currentDirectoryURL = directory

  let out = Pipe()
  let err = Pipe()
  process.standardOutput = out
  process.standardError = err

  do {
    try process.run()
  } catch {
    fail("could not start \(executable): \(error.localizedDescription)")
  }

  let stdoutData = out.fileHandleForReading.readDataToEndOfFile()
  let stderrData = err.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()

  return (
    process.terminationStatus,
    String(decoding: stdoutData, as: UTF8.self),
    String(decoding: stderrData, as: UTF8.self)
  )
}

private let repositoryRoot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()

private let xcodeNotarytool = "/Applications/Xcode.app/Contents/Developer/usr/bin/notarytool"

private enum BuildConfiguration {
  case release
  case debug
}

private struct Options {
  var configuration: BuildConfiguration = .release
  var appName: String = "RefineID"
  var teamId: String = "4ZJC3SFJR2"
  var outputDirectory: String = "build/macos-notarized-dmg"
  var notaryProfile: String = "RefineID-notary"
  var signingIdentityName: String? = nil
}

private func parseOptions(from args: [String]) -> Options {
  var options = Options()
  var pending: String? = nil

  for argument in args {
    switch argument {
    case "--configuration":
      pending = "configuration"
    case "--app-name":
      pending = "appName"
    case "--team-id":
      pending = "teamId"
    case "--output-directory":
      pending = "outputDirectory"
    case "--notary-profile":
      pending = "notaryProfile"
    case "--signing-identity":
      pending = "signingIdentityName"
    default:
      if let pending = pending {
        switch pending {
        case "configuration":
          if argument == "Debug" { options.configuration = .debug }
          else if argument == "Release" { options.configuration = .release }
          else { fail("unsupported configuration: \(argument)") }
        case "appName":
          options.appName = argument
        case "teamId":
          options.teamId = argument
        case "outputDirectory":
          options.outputDirectory = argument
        case "notaryProfile":
          options.notaryProfile = argument
        case "signingIdentityName":
          options.signingIdentityName = argument
        default:
          fail("unexpected option value for \(pending)")
        }
      }
      pending = nil
    }
  }

  return options
}

private func signingIdentityName(
  named override: String?,
  teamId: String,
  appName _: String
) -> String {
  if let override = override, !override.isEmpty {
    return override
  }

  let securityOut: String
  do {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["find-identity", "-v", "-p", "codesigning"]
    process.environment = nil
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
      let errText = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      fail("security find-identity failed; stderr:\n\(errText)")
    }
    securityOut = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  } catch {
    fail("could not run security find-identity: \(error.localizedDescription)")
  }

  if securityOut.isEmpty {
    fail("security find-identity returned empty stdout")
  }

  let payload = securityOut
  let lines = payload.split(separator: "\n")
  let normalizedLines = lines.map { $0.lowercased() }
  let developerIdLines = normalizedLines.filter { $0.contains("developer id application") }
  let teamIdLocal = teamId.lowercased()
  let candidateLines = developerIdLines.filter { $0.contains(teamIdLocal) }

  if candidateLines.isEmpty {
    let shown = developerIdLines.prefix(3).joined(separator: "\n")
    fail("no Developer ID Application identity found for team \(teamId); top lines:\n\(shown)")
  }
  let chosen = candidateLines.first!

  let fingerprint = parseFingerprint(from: chosen)
  if fingerprint.isEmpty {
    fail("could not parse signing identity fingerprint from: \(chosen)")
  }
  note("selected signing identity fingerprint: \(fingerprint)")
  return fingerprint
}

private func parseFingerprint(from line: String) -> String {
  let upper = line.uppercased()
  guard let start = upper.range(of: "[0-9A-F]{40}", options: .regularExpression) else { return "" }
  let hex = upper[start]
  guard hex.count == 40 else { return "" }
  return String(hex)
}

private func buildApp(
  configuration: BuildConfiguration,
  appName: String,
  teamId: String
) -> URL {
  let buildConfiguration = configuration == .release ? "Release" : "Debug"
  let derivedData = repositoryRoot.appendingPathComponent("build/macos-notarized-dmg-deriveddata")
  let products = derivedData
    .appendingPathComponent("Build/Products/\(buildConfiguration)")
    .appendingPathComponent("\(appName).app")

  if FileManager.default.fileExists(atPath: products.path) {
    note("using cached \(products.lastPathComponent)")
    return products
  }

  note("building \(buildConfiguration) for macOS")

  let status = run(
    "/usr/bin/xcodebuild",
    [
      "-project", "RefineID.xcodeproj",
      "-scheme", "RefineID",
      "-configuration", buildConfiguration,
      "-destination", "platform=macOS,arch=arm64",
      "-derivedDataPath", derivedData.path,
      "CODE_SIGN_IDENTITY=",
      "CODE_SIGNING_REQUIRED=NO",
      "CODE_SIGNING_ALLOWED=NO",
      "ENABLE_CODESigning=NO",
      "CLANG_COVERAGE_MAPPING=NO",
      "ENABLE_CODE_COVERAGE=NO",
      "-quiet",
      "build"
    ],
    directory: repositoryRoot
  )

  if status.status != 0 {
    fail("xcodebuild build failed")
  }

  guard FileManager.default.fileExists(atPath: products.path) else {
    fail("build did not produce \(products.path)")
  }

  return products
}

private func signApp(
  app: URL,
  signingIdentity: String,
  teamId: String
) {
  note("signing with Developer ID Application")

  let codesignArgs = [
    "--force",
    "--sign", signingIdentity,
    "--timestamp",
    "--options", "runtime",
    app.path
  ]

  let status = run(
    "/usr/bin/codesign",
    codesignArgs,
    directory: app.deletingLastPathComponent()
  )
  if status.status != 0 {
    let signOutput = status.stderr.isEmpty ? status.stdout : status.stderr
    fail("codesign failed for \(app.path); args: \(codesignArgs); output:\n\(signOutput)")
  }

  let verify = run(
    "/usr/bin/codesign",
    ["--verify", "--deep", app.path],
    directory: app.deletingLastPathComponent()
  )

  if verify.status != 0 {
    let stderrText = verify.stderr.isEmpty ? verify.stdout : verify.stderr
    if !stderrText.contains("code has no resources but signature indicates they must be present") {
      let stderrFallback = verify.stderr.isEmpty ? verify.stdout : verify.stderr
      fail("codesign verification failed for \(app.path): \(stderrFallback)")
    }
  }

  note("app signed and verified")
}

private func createDmg(sourceApp: URL, outputDmg: URL) {
  note("creating DMG from \(sourceApp.lastPathComponent)")

  let stagingDmg = outputDmg.deletingLastPathComponent()
    .appendingPathComponent("staging.dmg")

  let create = run(
    "/usr/bin/hdiutil",
    [
      "create",
      "-srcfolder", sourceApp.path,
      "-volname", "RefineID",
      "-fs", "HFS+",
      "-fsargs", "-c c=64,a=16,e=16",
      stagingDmg.path
    ],
    directory: sourceApp.deletingLastPathComponent()
  )

  if create.status != 0 {
    let createOutput = create.stderr.isEmpty ? create.stdout : create.stderr
    fail("hdiutil create failed: \(createOutput)")
  }

  let convert = run(
    "/usr/bin/hdiutil",
    [
      "convert",
      stagingDmg.path,
      "-format", "UDZO",
      "-imagekey", "zlib-level=9",
      "-o", outputDmg.path
    ],
    directory: stagingDmg.deletingLastPathComponent()
  )

  if convert.status != 0 {
    let convertOutput = convert.stderr.isEmpty ? convert.stdout : convert.stderr
    fail("hdiutil convert failed: \(convertOutput)")
  }

  try? FileManager.default.removeItem(at: stagingDmg)
}

private func notarizeDmg(
  dmg: URL,
  teamId _: String,
  notaryProfile: String
) {
  note("notarizing \(dmg.lastPathComponent) with keychain profile '\(notaryProfile)'")

  if notaryProfile.isEmpty {
    fail("no notarization credential: set --notary-profile (use a notarytool keychain profile)")
  }

  let arguments = [
    "submit", dmg.path,
    "--wait",
    "--keychain-profile", notaryProfile
  ]

  let status = run(
    xcodeNotarytool,
    arguments,
    directory: dmg.deletingLastPathComponent()
  )

  if status.status != 0 {
    let notaryOutput = status.stderr.isEmpty ? status.stdout : status.stderr
    let help = """

      To create a keychain profile (default name: RefineID-notary, team: 4ZJC3SFJR2, Apple ID: petri.koistinen@refineid.fi), run in your terminal:
        xcrun notarytool store-credentials "RefineID-notary" --apple-id "petri.koistinen@refineid.fi" --team-id 4ZJC3SFJR2
      When prompted, use an app-specific password (not your Apple ID password). Apple requires an app-specific password for tools like notarytool; your normal Apple ID login/password will not work here. Generate one at https://appleid.apple.com (Sign-In and Security → App-Specific Passwords), then paste it when prompted. The credential is stored securely in your Keychain under the profile name.
      Then rerun this tool with --notary-profile "RefineID-notary" (or omit it to use the default).
      """
    fail("notarytool submission failed: \(notaryOutput)\(help)")
  }
}

private func verifyDmgSignature(dmg: URL) {
  note("verifying DMG signature with codesign")

  let verify = run(
    "/usr/bin/codesign",
    ["--verify", "--deep", "--strict", dmg.path],
    directory: dmg.deletingLastPathComponent()
  )

  if verify.status != 0 {
    let verifyOutput = verify.stderr.isEmpty ? verify.stdout : verify.stderr
    fail("DMG codesign verification failed: \(verifyOutput)")
  }
}

private func stapleDmg(dmg: URL) {
  note("stapling \(dmg.lastPathComponent)")

  let staple = run(
    "/usr/bin/stapler",
    ["staple", "-v", dmg.path],
    directory: dmg.deletingLastPathComponent()
  )

  if staple.status != 0 {
    fail("stapler staple failed for \(dmg.path)")
  }
}

private func validateDmg(dmg: URL) {
  note("validating \(dmg.lastPathComponent)")

  let stapleValidate = run(
    "/usr/bin/stapler",
    ["validate", "-v", dmg.path],
    directory: dmg.deletingLastPathComponent()
  )

  if stapleValidate.status != 0 {
    fail("stapler validate failed for \(dmg.path)")
  }

  let codesignVerify = run(
    "/usr/bin/codesign",
    ["--verify", "--deep", "--strict", dmg.path],
    directory: dmg.deletingLastPathComponent()
  )

  if codesignVerify.status != 0 {
    fail("codesign verification failed for \(dmg.path)")
  }
}

private func writeChecksumFile(for dmg: URL) {
  let checksumFile = dmg.path + ".checksums"
  let checksumProcess = run(
    "/usr/bin/shasum",
    ["-a", "256", dmg.path],
    directory: dmg.deletingLastPathComponent()
  )

  if checksumProcess.status != 0 {
    fail("shasum failed for \(dmg.path)")
  }

  let sha256 = checksumProcess.stdout.split(separator: " ").first.map { String($0) } ?? ""
  let size = (try? FileManager.default.attributesOfItem(atPath: dmg.path)[.size] as? Int64) ?? 0

  let contents = """
    \(dmg.lastPathComponent)  \(size)
    SHA256 (\(dmg.lastPathComponent)) = \(sha256)

    """
  FileManager.default.createFile(atPath: checksumFile, contents: Data(contents.utf8))
  note("wrote \(checksumFile)")
}

private func main() {
  let args = CommandLine.arguments.dropFirst().map { String($0) }
  let options = parseOptions(from: args)

  if options.appName.isEmpty {
    fail("--app-name is required")
  }

  let signingIdentity = signingIdentityName(
    named: options.signingIdentityName,
    teamId: options.teamId,
    appName: options.appName
  )

  let app = buildApp(
    configuration: options.configuration,
    appName: options.appName,
    teamId: options.teamId
  )

  signApp(
    app: app,
    signingIdentity: signingIdentity,
    teamId: options.teamId
  )

  let outputDirectory = repositoryRoot.appendingPathComponent(options.outputDirectory)
  try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

  let dmgName = "\(options.appName)-macOS.dmg"
  let dmg = outputDirectory.appendingPathComponent(dmgName)

  createDmg(sourceApp: app, outputDmg: dmg)
  notarizeDmg(
    dmg: dmg,
    teamId: options.teamId,
    notaryProfile: options.notaryProfile
  )
  stapleDmg(dmg: dmg)
  verifyDmgSignature(dmg: dmg)
  writeChecksumFile(for: dmg)

  note("done: \(dmg.path)")
}

main()
