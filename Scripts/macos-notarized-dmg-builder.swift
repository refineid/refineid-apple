#!/usr/bin/env swift
// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// Builds a Developer ID signed, notarized, stapled macOS DMG for direct
// distribution. This is a direct-download artifact path only. It is separate
// from the App Store release manager and does not upload to App Store Connect.
//
// Steps:
//   1. Build the macOS app from the current checkout, rebuilding whenever a
//      build input is newer than the last recorded build stamp.
//   2. Sign it with Developer ID Application.
//   3. Package it into a DMG that installs by dragging onto /Applications.
//   4. Notarize the DMG with notarytool.
//   5. Staple the notarization ticket.
//   6. Validate the stapled ticket.
//   7. Write a checksum file next to the DMG.

import Foundation

private let fingerprintHexDigitCount = 40
private let shownIdentityLineCount = 3
private let checksumLengthBytes = 64
private let flagArgumentWidth = 1
private let valuedArgumentWidth = 2
private let buildStampFileName = "build-input-stamp"

/// The committed release configuration: the marketing version and the team
/// the app signs with. Both are public and belong to the checkout.
private func versionConfigPath() -> URL {
  repositoryRoot.appendingPathComponent("Version.xcconfig")
}

private func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("ERROR: \(message)\n".utf8))
  exit(1)
}

private func note(_ message: String) {
  print("ok: \(message)")
}

private struct CommandResult {
  let status: Int32
  let stdout: String
  let stderr: String

  var failed: Bool { status != 0 }

  /// stderr when the command wrote any, stdout otherwise.
  var message: String { stderr.isEmpty ? stdout : stderr }
}

/// Runs a command and returns its output. stderr goes to a temporary file so
/// neither pipe can fill while the other is still unread.
private func run(
  _ executable: String,
  _ arguments: [String],
  directory: URL? = nil
) -> CommandResult {
  let errorURL = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString + "-stderr")
  guard FileManager.default.createFile(atPath: errorURL.path, contents: nil),
    let errorHandle = FileHandle(forWritingAtPath: errorURL.path)
  else {
    fail("could not create \(errorURL.path)")
  }
  defer { try? FileManager.default.removeItem(at: errorURL) }

  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.currentDirectoryURL = directory

  let out = Pipe()
  process.standardOutput = out
  process.standardError = errorHandle

  do {
    try process.run()
  } catch {
    try? errorHandle.close()
    fail("could not start \(executable): \(error.localizedDescription)")
  }

  let stdoutData = out.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  try? errorHandle.close()

  let stderrData = (try? Data(contentsOf: errorURL)) ?? Data()

  return CommandResult(
    status: process.terminationStatus,
    stdout: String(bytes: stdoutData, encoding: .utf8) ?? "",
    stderr: String(bytes: stderrData, encoding: .utf8) ?? "",
  )
}

private let repositoryRoot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()

/// Build inputs whose modification time decides whether a cached app is stale.
private let buildInputPaths = [
  "CardCore",
  "Config",
  "Metadata",
  "PKCS11Bridge",
  "RefineID.xcodeproj",
  "Sources",
  "Version.xcconfig",
]

private let skippedDirectoryNames: Set<String> = [
  ".build",
  ".swiftpm",
  "build",
  "derivedData",
]

private func resolveNotarytool() -> String {
  let found = run("/usr/bin/xcrun", ["--find", "notarytool"], directory: repositoryRoot)
  if !found.failed {
    let path = found.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
      return path
    }
  }

  let xcodePath = "/Applications/Xcode.app/Contents/Developer/usr/bin/notarytool"
  if FileManager.default.isExecutableFile(atPath: xcodePath) {
    return xcodePath
  }

  fail("could not find notarytool; select an Xcode installation with xcode-select")
}

/// Reads a key from `Version.xcconfig`. Returns nil when the key is absent or
/// empty.
private func xcconfigValue(_ key: String) -> String? {
  guard let contents = try? String(contentsOf: versionConfigPath(), encoding: .utf8) else {
    fail("could not read \(key) from \(versionConfigPath().path)")
  }

  for line in contents.components(separatedBy: .newlines) {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix(key) else { continue }
    guard let equals = trimmed.firstIndex(of: "=") else { continue }
    let value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
    if !value.isEmpty {
      return value
    }
  }

  return nil
}

private func marketingVersion() -> String {
  guard let version = xcconfigValue("MARKETING_VERSION") else {
    fail("MARKETING_VERSION not found in \(versionConfigPath().path)")
  }
  return version
}

/// The signing team is public and lives in the checkout, so a build signs under
/// the team the source declares instead of a constant that can drift from it.
/// `--team-id` overrides this for a temporary certificate or another checkout.
private func developmentTeam() -> String {
  guard let team = xcconfigValue("DEVELOPMENT_TEAM") else {
    fail("DEVELOPMENT_TEAM not found in \(versionConfigPath().path)")
  }
  return team
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

private enum BuildConfiguration: String {
  case debug = "Debug"
  case release = "Release"
}

private struct Options {
  var configuration = BuildConfiguration.release
  var appName = "RefineID"
  var teamId: String?
  var outputDirectory = "build/macos-notarized-dmg"
  var notaryProfile = "RefineID-notary"
  var signingIdentityName: String?
  var forceRebuild = false
  var overwrite = false
}

private func applyOption(name: String, value: String, to options: inout Options) {
  switch name {
  case "--configuration":
    guard let configuration = BuildConfiguration(rawValue: value) else {
      fail("unsupported configuration: \(value) (use Debug or Release)")
    }
    options.configuration = configuration
  case "--app-name":
    options.appName = value
  case "--team-id":
    options.teamId = value
  case "--output-directory":
    options.outputDirectory = value
  case "--notary-profile":
    options.notaryProfile = value
  case "--signing-identity":
    options.signingIdentityName = value
  default:
    fail("unknown option: \(name)")
  }
}

private func parseOptions(from args: [String]) -> Options {
  var options = Options()
  var index = 0

  while index < args.count {
    let name = args[index]
    switch name {
    case "--force-rebuild":
      options.forceRebuild = true
      index += flagArgumentWidth
    case "--overwrite":
      options.overwrite = true
      index += flagArgumentWidth
    case "--configuration", "--app-name", "--team-id", "--output-directory",
      "--notary-profile", "--signing-identity":
      let valueIndex = index + flagArgumentWidth
      guard valueIndex < args.count else {
        fail("missing value for \(name)")
      }
      applyOption(name: name, value: args[valueIndex], to: &options)
      index += valuedArgumentWidth
    default:
      fail("unknown option: \(name)")
    }
  }

  if options.appName.isEmpty {
    fail("--app-name is required")
  }
  if let teamId = options.teamId, teamId.isEmpty {
    fail("--team-id must not be empty")
  }

  return options
}

private func modificationDate(of url: URL) -> Date? {
  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
  return values?.contentModificationDate
}

private func newestBuildInputDate() -> Date? {
  var newest: Date?

  func consider(_ url: URL) {
    guard let date = modificationDate(of: url) else { return }
    if let current = newest, current >= date { return }
    newest = date
  }

  for path in buildInputPaths {
    let root = repositoryRoot.appendingPathComponent(path)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
      continue
    }
    guard isDirectory.boolValue else {
      consider(root)
      continue
    }
    guard
      let walker = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.contentModificationDateKey]
      )
    else {
      continue
    }
    for case let item as URL in walker {
      if skippedDirectoryNames.contains(item.lastPathComponent) {
        walker.skipDescendants()
        continue
      }
      consider(item)
    }
  }

  return newest
}

/// The newest build-input time recorded by the last successful build.
///
/// Comparing inputs against this record, rather than against the product's own
/// modification time, keeps the answer stable: xcodebuild leaves an unchanged
/// bundle untouched, while a checkout or a rebase moves every input.
private func recordedBuildInputDate(derivedData: URL) -> Date? {
  let stampFile = derivedData.appendingPathComponent(buildStampFileName)
  guard let text = try? String(contentsOf: stampFile, encoding: .utf8) else { return nil }
  guard let seconds = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
    return nil
  }
  return Date(timeIntervalSince1970: seconds)
}

private func recordBuildInputDate(derivedData: URL) {
  guard let newest = newestBuildInputDate() else { return }
  let stampFile = derivedData.appendingPathComponent(buildStampFileName)
  do {
    try String(newest.timeIntervalSince1970).write(to: stampFile, atomically: true, encoding: .utf8)
  } catch {
    fail("could not write \(stampFile.path): \(error.localizedDescription)")
  }
}

/// True when a build input changed after the recorded build, so reusing the
/// cache would package a binary that no longer matches the tree.
private func cachedAppIsStale(derivedData: URL) -> Bool {
  guard let recorded = recordedBuildInputDate(derivedData: derivedData) else { return true }
  guard let newest = newestBuildInputDate() else { return false }
  return newest > recorded
}

private func signingIdentityName(named override: String?, teamId: String) -> String {
  if let override, !override.isEmpty {
    return override
  }

  let result = run(
    "/usr/bin/security",
    ["find-identity", "-v", "-p", "codesigning"],
    directory: repositoryRoot
  )

  if result.failed {
    fail("security find-identity failed:\n\(result.message)")
  }
  if result.stdout.isEmpty {
    fail("security find-identity returned empty stdout")
  }

  let lines = result.stdout.split(separator: "\n").map { $0.lowercased() }
  let developerIdLines = lines.filter { $0.contains("developer id application") }
  let teamIdLocal = teamId.lowercased()
  let candidateLines = developerIdLines.filter { $0.contains(teamIdLocal) }

  guard let chosen = candidateLines.first else {
    let shown = developerIdLines.prefix(shownIdentityLineCount).joined(separator: "\n")
    fail("no Developer ID Application identity found for team \(teamId); top lines:\n\(shown)")
  }

  let fingerprint = parseFingerprint(from: chosen)
  if fingerprint.isEmpty {
    fail("could not parse signing identity fingerprint from: \(chosen)")
  }
  note("selected signing identity fingerprint: \(fingerprint)")
  return fingerprint
}

private func parseFingerprint(from line: String) -> String {
  let upper = line.uppercased()
  let pattern = "[0-9A-F]{\(fingerprintHexDigitCount)}"
  guard let range = upper.range(of: pattern, options: .regularExpression) else { return "" }
  let hex = upper[range]
  guard hex.count == fingerprintHexDigitCount else { return "" }
  return String(hex)
}

private func buildApp(
  configuration: BuildConfiguration,
  appName: String,
  forceRebuild: Bool
) -> URL {
  let derivedData = repositoryRoot.appendingPathComponent("build/macos-notarized-dmg-deriveddata")
  let products =
    derivedData
    .appendingPathComponent("Build/Products/\(configuration.rawValue)")
    .appendingPathComponent("\(appName).app")

  let cached = FileManager.default.fileExists(atPath: products.path)
  if cached, !forceRebuild, !cachedAppIsStale(derivedData: derivedData) {
    note("using cached \(products.lastPathComponent)")
    return products
  }
  if cached {
    note(
      forceRebuild
        ? "rebuilding \(appName) (--force-rebuild)"
        : "rebuilding \(appName) (build input is newer than the cached app)"
    )
  }

  note("building \(configuration.rawValue) for macOS")

  let result = run(
    "/usr/bin/xcodebuild",
    [
      "-project", "RefineID.xcodeproj",
      "-scheme", "RefineID",
      "-configuration", configuration.rawValue,
      "-destination", "platform=macOS,arch=arm64",
      "-derivedDataPath", derivedData.path,
      "CODE_SIGN_IDENTITY=",
      "CODE_SIGNING_REQUIRED=NO",
      "CODE_SIGNING_ALLOWED=NO",
      "CLANG_COVERAGE_MAPPING=NO",
      "ENABLE_CODE_COVERAGE=NO",
      "-quiet",
      "build",
    ],
    directory: repositoryRoot
  )

  if result.failed {
    fail("xcodebuild build failed:\n\(result.message)")
  }

  guard FileManager.default.fileExists(atPath: products.path) else {
    fail("build did not produce \(products.path)")
  }

  recordBuildInputDate(derivedData: derivedData)

  return products
}

private func resolvedEntitlements(templatePath: String, teamId: String) -> URL? {
  let templateURL = repositoryRoot.appendingPathComponent(templatePath)
  guard let data = try? Data(contentsOf: templateURL),
    var text = String(data: data, encoding: .utf8)
  else {
    return nil
  }
  text = text.replacingOccurrences(of: "$(AppIdentifierPrefix)", with: "\(teamId).")
  let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent(UUID().uuidString + "-" + templateURL.lastPathComponent)
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
    "--options", "runtime",
  ]
  if let entitlements {
    arguments += ["--entitlements", entitlements.path]
  }
  arguments.append(path.path)

  let result = run(
    "/usr/bin/codesign",
    arguments,
    directory: path.deletingLastPathComponent()
  )
  if result.failed {
    fail("codesign failed for \(path.path):\n\(result.message)")
  }
}

private func signApp(
  app: URL,
  signingIdentity: String,
  teamId: String
) {
  note("signing with Developer ID Application")

  // The direct-download build reuses the App Store entitlement templates, so
  // the same capabilities are provisioned under Developer ID signing. Only the
  // team prefix placeholder needs resolving.
  let tokenEntitlements = resolvedEntitlements(
    templatePath: "Config/TokenExtension.entitlements",
    teamId: teamId
  )
  let appEntitlements = resolvedEntitlements(
    templatePath: "Config/RefineID-Store.entitlements",
    teamId: teamId
  )
  defer {
    if let tokenEntitlements { try? FileManager.default.removeItem(at: tokenEntitlements) }
    if let appEntitlements { try? FileManager.default.removeItem(at: appEntitlements) }
  }

  // Sign nested components inside out before signing bundles and the app.
  let nestedBundles: [URL] = [
    app.appendingPathComponent(
      "Contents/PlugIns/RefineIDTokenExtension.appex/Contents/Resources/CardCore_CardCore.bundle"
    ),
    app.appendingPathComponent("Contents/Resources/CardCore_CardCore.bundle"),
  ].filter { FileManager.default.fileExists(atPath: $0.path) }

  let tokenExecutable = app.appendingPathComponent(
    "Contents/PlugIns/RefineIDTokenExtension.appex/Contents/MacOS/RefineIDTokenExtension"
  )
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
    ["--verify", "--strict", "--verbose=2", app.path],
    directory: app.deletingLastPathComponent()
  )

  if verify.failed {
    fail("codesign verification failed for \(app.path):\n\(verify.message)")
  }

  note("app signed and verified")
}

/// Builds the staging directory that becomes the DMG volume: the signed app
/// and an Applications link, so installing is a drag onto /Applications.
private func stageDmgContents(sourceApp: URL) -> URL {
  let stagingDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString + "-dmg-staging")
  do {
    try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
  } catch {
    fail("could not create \(stagingDirectory.path): \(error.localizedDescription)")
  }

  note("staging \(sourceApp.lastPathComponent) with an /Applications link")

  // ditto keeps the code signature and extended attributes intact.
  let stagedApp = stagingDirectory.appendingPathComponent(sourceApp.lastPathComponent)
  let copy = run("/usr/bin/ditto", [sourceApp.path, stagedApp.path], directory: stagingDirectory)
  if copy.failed {
    fail("could not copy \(sourceApp.path) into the DMG staging directory:\n\(copy.message)")
  }

  let applicationsLink = stagingDirectory.appendingPathComponent("Applications")
  do {
    try FileManager.default.createSymbolicLink(
      at: applicationsLink,
      withDestinationURL: URL(fileURLWithPath: "/Applications", isDirectory: true)
    )
  } catch {
    fail("could not add the /Applications link: \(error.localizedDescription)")
  }

  return stagingDirectory
}

private func createDmg(
  sourceApp: URL,
  outputDmg: URL,
  volumeName: String,
  overwrite: Bool
) {
  if FileManager.default.fileExists(atPath: outputDmg.path), !overwrite {
    fail("\(outputDmg.path) already exists; pass --overwrite to replace it")
  }

  let stagingDmg = outputDmg.deletingLastPathComponent()
    .appendingPathComponent("staging.dmg")
  try? FileManager.default.removeItem(at: stagingDmg)
  if FileManager.default.fileExists(atPath: outputDmg.path) {
    try? FileManager.default.removeItem(at: outputDmg)
  }

  let stagingDirectory = stageDmgContents(sourceApp: sourceApp)
  defer { try? FileManager.default.removeItem(at: stagingDirectory) }

  note("creating DMG from \(sourceApp.lastPathComponent)")

  let create = run(
    "/usr/bin/hdiutil",
    [
      "create",
      "-srcfolder", stagingDirectory.path,
      "-volname", volumeName,
      "-fs", "HFS+",
      "-fsargs", "-c c=64,a=16,e=16",
      stagingDmg.path,
    ],
    directory: stagingDirectory
  )

  if create.failed {
    fail("hdiutil create failed: \(create.message)")
  }

  let convert = run(
    "/usr/bin/hdiutil",
    [
      "convert",
      stagingDmg.path,
      "-format", "UDZO",
      "-imagekey", "zlib-level=9",
      "-o", outputDmg.path,
    ],
    directory: stagingDmg.deletingLastPathComponent()
  )

  if convert.failed {
    fail("hdiutil convert failed: \(convert.message)")
  }

  try? FileManager.default.removeItem(at: stagingDmg)
}

private func notarizationSetupInstructions(for profile: String) -> String {
  let rerun =
    profile == "RefineID-notary"
    ? "swift Scripts/macos-notarized-dmg-builder.swift --configuration Release"
    : "swift Scripts/macos-notarized-dmg-builder.swift --configuration Release --notary-profile \"\(profile)\""

  return """

    Notarization credentials not found. Do this once:

    1. Use the App Store Connect API key (.p8) that already signs the app, and
       note its Key ID and Issuer ID.

    2. Store it in your Keychain as the notarytool profile "\(profile)":
       xcrun notarytool store-credentials "\(profile)" \\
         --key <path-to-AuthKey.p8> \\
         --key-id <key-id> \\
         --issuer <issuer-id>

    3. Rerun: \(rerun)
    """
}

private func missingNotaryProfileMessage(_ output: String, profile: String) -> String {
  let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.contains("No Keychain password item found") || trimmed.contains("Could not find") {
    return "Keychain profile '\(profile)' not found.\(notarizationSetupInstructions(for: profile))"
  }
  return "notarytool failed: \(trimmed)\(notarizationSetupInstructions(for: profile))"
}

private func preflightNotaryProfile(_ notaryProfile: String, notarytool: String) {
  if notaryProfile.isEmpty {
    fail("no notarization credential: set --notary-profile (use a notarytool keychain profile)")
  }

  let result = run(
    notarytool,
    ["history", "--keychain-profile", notaryProfile],
    directory: repositoryRoot
  )

  guard result.failed else { return }

  let output = result.message
  if output.contains("No Keychain password item found") || output.contains("Could not find") {
    fail(missingNotaryProfileMessage(output, profile: notaryProfile))
  }

  // Any other failure is reported as it is: a network or service problem must
  // not read as missing credentials.
  fail(
    "notarytool profile check failed for '\(notaryProfile)': "
      + output.trimmingCharacters(in: .whitespacesAndNewlines)
  )
}

private func notarizeDmg(
  dmg: URL,
  notaryProfile: String,
  notarytool: String
) {
  note("notarizing \(dmg.lastPathComponent) with keychain profile '\(notaryProfile)'")

  if notaryProfile.isEmpty {
    fail("no notarization credential: set --notary-profile (use a notarytool keychain profile)")
  }

  let result = run(
    notarytool,
    ["submit", dmg.path, "--wait", "--keychain-profile", notaryProfile],
    directory: dmg.deletingLastPathComponent()
  )

  if result.failed {
    let output = result.message
    if output.contains("No Keychain password item found") || output.contains("Could not find") {
      fail(missingNotaryProfileMessage(output, profile: notaryProfile))
    }
    fail("notarytool submission failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
  }
}

private func stapleDmg(dmg: URL) {
  note("stapling \(dmg.lastPathComponent)")

  let result = run(
    "/usr/bin/stapler",
    ["staple", "-v", dmg.path],
    directory: dmg.deletingLastPathComponent()
  )

  if result.failed {
    fail("stapler staple failed for \(dmg.path): \(result.message)")
  }
}

private func validateDmg(dmg: URL) {
  note("validating the stapled ticket on \(dmg.lastPathComponent)")

  let result = run(
    "/usr/bin/stapler",
    ["validate", "-v", dmg.path],
    directory: dmg.deletingLastPathComponent()
  )

  if result.failed {
    fail("stapler validate failed for \(dmg.path): \(result.message)")
  }
}

private func writeChecksumFile(for dmg: URL) {
  let checksumFile = dmg.path + ".checksums"
  let result = run(
    "/usr/bin/shasum",
    ["-a", "256", dmg.path],
    directory: dmg.deletingLastPathComponent()
  )

  if result.failed {
    fail("shasum failed for \(dmg.path): \(result.message)")
  }

  let sha256 = result.stdout.split(separator: " ").first.map(String.init) ?? ""
  guard sha256.count == checksumLengthBytes else {
    fail("shasum produced an unexpected digest for \(dmg.path)")
  }

  let size = (try? FileManager.default.attributesOfItem(atPath: dmg.path)[.size] as? Int64) ?? 0
  let contents = """
    \(dmg.lastPathComponent)  \(size)
    SHA256 (\(dmg.lastPathComponent)) = \(sha256)

    """

  do {
    try Data(contents.utf8).write(to: URL(fileURLWithPath: checksumFile), options: .atomic)
  } catch {
    fail("could not write \(checksumFile): \(error.localizedDescription)")
  }

  note("wrote \(checksumFile)")
}

private func main() {
  let args = CommandLine.arguments.dropFirst().map { String($0) }
  let options = parseOptions(from: args)
  let teamId = options.teamId ?? developmentTeam()
  let notarytool = resolveNotarytool()

  preflightNotaryProfile(options.notaryProfile, notarytool: notarytool)

  let signingIdentity = signingIdentityName(
    named: options.signingIdentityName,
    teamId: teamId
  )

  let app = buildApp(
    configuration: options.configuration,
    appName: options.appName,
    forceRebuild: options.forceRebuild
  )

  signApp(
    app: app,
    signingIdentity: signingIdentity,
    teamId: teamId
  )

  let outputDirectory = repositoryRoot.appendingPathComponent(options.outputDirectory)
  do {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
  } catch {
    fail("could not create \(outputDirectory.path): \(error.localizedDescription)")
  }

  let dmg = outputDirectory.appendingPathComponent(dmgFileName(appName: options.appName))

  createDmg(
    sourceApp: app,
    outputDmg: dmg,
    volumeName: options.appName,
    overwrite: options.overwrite
  )
  notarizeDmg(dmg: dmg, notaryProfile: options.notaryProfile, notarytool: notarytool)
  stapleDmg(dmg: dmg)
  validateDmg(dmg: dmg)
  writeChecksumFile(for: dmg)

  note("done: \(dmg.path)")
}

main()
