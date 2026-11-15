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

private func marketingVersion() -> String {
  let versionFile = repositoryRoot.appendingPathComponent("Version.xcconfig")
  guard let contents = try? String(contentsOf: versionFile, encoding: .utf8) else {
    fail("could not read marketing version from \(versionFile.path)")
  }

  for line in contents.components(separatedBy: .newlines) {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("MARKETING_VERSION") else { continue }
    guard let equals = trimmed.firstIndex(of: "=") else { continue }
    let value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
    if !value.isEmpty {
      return value
    }
  }

  fail("MARKETING_VERSION not found in \(versionFile.path)")
}

private func utcBuildTimeStamp() -> String {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  formatter.dateFormat = "HHmm"
  return formatter.string(from: Date())
}

private func dmgFileName(appName: String) -> String {
  "\(appName)-v\(marketingVersion()).\(utcBuildTimeStamp()).dmg"
}

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

private func resolvedEntitlements(templatePath: String, teamId: String) -> URL? {
  let templateURL = repositoryRoot.appendingPathComponent(templatePath)
  guard let data = try? Data(contentsOf: templateURL),
        var text = String(data: data, encoding: .utf8) else {
    return nil
  }
  text = text.replacingOccurrences(of: "$(AppIdentifierPrefix)", with: "\(teamId).")
  let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent(UUID().uuidString + "-" + (templateURL.lastPathComponent))
  do {
    try text.write(to: tempURL, atomically: true, encoding: .utf8)
    return tempURL
  } catch {
    return nil
  }
}

private func codesignItem(
  _ path: URL,
  identity: String,
  entitlements: URL? = nil
) {
  var arguments = [
    "--force",
    "--sign", identity,
    "--timestamp",
    "--options", "runtime"
  ]
  if let entitlements = entitlements {
    arguments += ["--entitlements", entitlements.path]
  }
  arguments.append(path.path)

  let status = run(
    "/usr/bin/codesign",
    arguments,
    directory: path.deletingLastPathComponent()
  )
  if status.status != 0 {
    let output = status.stderr.isEmpty ? status.stdout : status.stderr
    fail("codesign failed for \(path.path):\n\(output)")
  }
}

private func signApp(
  app: URL,
  signingIdentity: String,
  teamId: String
) {
  note("signing with Developer ID Application")

  let tokenEntitlements = resolvedEntitlements(templatePath: "Config/TokenExtension.entitlements", teamId: teamId)
  let appEntitlements = resolvedEntitlements(templatePath: "Config/RefineID-Store.entitlements", teamId: teamId)
  defer {
    if let tokenEntitlements { try? FileManager.default.removeItem(at: tokenEntitlements) }
    if let appEntitlements { try? FileManager.default.removeItem(at: appEntitlements) }
  }

  // Sign nested components inside-out before signing bundles and the app.
  let nestedBundles: [URL] = [
    app.appendingPathComponent("Contents/PlugIns/RefineIDTokenExtension.appex/Contents/Resources/CardCore_CardCore.bundle"),
    app.appendingPathComponent("Contents/Resources/CardCore_CardCore.bundle"),
  ].filter { FileManager.default.fileExists(atPath: $0.path) }

  let tokenExecutable = app.appendingPathComponent("Contents/PlugIns/RefineIDTokenExtension.appex/Contents/MacOS/RefineIDTokenExtension")
  let tokenAppEx = app.appendingPathComponent("Contents/PlugIns/RefineIDTokenExtension.appex")
  let mainExecutable = app.appendingPathComponent("Contents/MacOS/RefineID")

  for bundle in nestedBundles {
    codesignItem(bundle, identity: signingIdentity)
  }

  if FileManager.default.fileExists(atPath: tokenExecutable.path) {
    codesignItem(tokenExecutable, identity: signingIdentity, entitlements: tokenEntitlements)
  }
  if FileManager.default.fileExists(atPath: tokenAppEx.path) {
    codesignItem(tokenAppEx, identity: signingIdentity)
  }
  if FileManager.default.fileExists(atPath: mainExecutable.path) {
    codesignItem(mainExecutable, identity: signingIdentity, entitlements: appEntitlements)
  }

  codesignItem(app, identity: signingIdentity)

  let verify = run(
    "/usr/bin/codesign",
    ["--verify", "--deep", "--strict", app.path],
    directory: app.deletingLastPathComponent()
  )

  if verify.status != 0 {
    let output = verify.stderr.isEmpty ? verify.stdout : verify.stderr
    fail("codesign verification failed for \(app.path):\n\(output)")
  }

  note("app signed and verified")
}

private func createDmg(sourceApp: URL, outputDmg: URL) {
  note("creating DMG from \(sourceApp.lastPathComponent)")

  let stagingDmg = outputDmg.deletingLastPathComponent()
    .appendingPathComponent("staging.dmg")

  try? FileManager.default.removeItem(at: stagingDmg)
  try? FileManager.default.removeItem(at: outputDmg)

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

private func notarizationSetupInstructions(for profile: String) -> String {
  let rerun = profile == "RefineID-notary"
    ? "swift Scripts/macos-notarized-dmg-builder.swift --configuration Release"
    : "swift Scripts/macos-notarized-dmg-builder.swift --configuration Release --notary-profile \"\(profile)\""

  return """

  Notarization credentials not found. Do this once:

  1. Create an app-specific password named "RefineID-notary" (not your Apple ID password):
     https://account.apple.com/account/manage → App-Specific Passwords
     (Apple Account app-specific password, not App Store Connect. You must sign in with your Apple ID password, not a passkey.)

  2. Store it in your Keychain as profile "\(profile)":
     xcrun notarytool store-credentials "\(profile)" --apple-id "petri.koistinen@refineid.fi" --team-id 4ZJC3SFJR2

  3. When prompted, paste the app-specific password.

  4. Rerun: \(rerun)
  """
}

private func missingNotaryProfileMessage(_ output: String, profile: String) -> String {
  let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.contains("No Keychain password item found") || trimmed.contains("Could not find") {
    return "Keychain profile '\(profile)' not found.\(notarizationSetupInstructions(for: profile))"
  }
  return "notarytool failed: \(trimmed)\(notarizationSetupInstructions(for: profile))"
}

private func preflightNotaryProfile(_ notaryProfile: String) {
  if notaryProfile.isEmpty {
    fail("no notarization credential: set --notary-profile (use a notarytool keychain profile)")
  }

  let status = run(
    xcodeNotarytool,
    ["history", "--keychain-profile", notaryProfile],
    directory: repositoryRoot
  )

  if status.status != 0 {
    let output = status.stderr.isEmpty ? status.stdout : status.stderr
    if output.contains("No Keychain password item found") || output.contains("Could not find") || status.status == 69 {
      fail(missingNotaryProfileMessage(output, profile: notaryProfile))
    }
    fail("notarytool profile check failed for '\(notaryProfile)': \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
  }
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
    if notaryOutput.contains("No Keychain password item found") || notaryOutput.contains("Could not find") {
      fail(missingNotaryProfileMessage(notaryOutput, profile: notaryProfile))
    }
    fail("notarytool submission failed: \(notaryOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
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
    let output = stapleValidate.stderr.isEmpty ? stapleValidate.stdout : stapleValidate.stderr
    fail("stapler validate failed for \(dmg.path): \(output)")
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

  preflightNotaryProfile(options.notaryProfile)

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

  let dmgName = dmgFileName(appName: options.appName)
  let dmg = outputDirectory.appendingPathComponent(dmgName)

  createDmg(sourceApp: app, outputDmg: dmg)
  notarizeDmg(
    dmg: dmg,
    teamId: options.teamId,
    notaryProfile: options.notaryProfile
  )
  stapleDmg(dmg: dmg)
  validateDmg(dmg: dmg)
  writeChecksumFile(for: dmg)

  note("done: \(dmg.path)")
}

main()
