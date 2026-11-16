#!/usr/bin/env swift
// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// Builds a Developer ID signed, notarized, stapled macOS DMG for direct
// distribution. This is a direct-download artifact path only. It is separate
// from the App Store release manager and does not upload to App Store Connect.
//
// The build's input is the annotated release tag, not a time stamp: the tree
// must be the commit the tag names, and that tag and commit are stamped into
// the app and carried by the file name. Nothing about the source is typed on
// the command line, so a published image cannot disagree with the commit it
// came from.
//
// Steps:
//   1. Refuse a tree that is not the commit an annotated release tag names.
//   2. Build the macOS app from the current checkout, rebuilding whenever a
//      build input or the source identity is newer than the last build stamp.
//   3. Sign it with Developer ID Application.
//   4. Package it into a DMG that installs by dragging onto /Applications.
//   5. Sign the disk image itself with Developer ID Application.
//   6. Notarize the DMG with notarytool.
//   7. Staple the notarization ticket.
//   8. Validate the stapled ticket.
//   9. Assess the artifact with Gatekeeper.
//  10. Write a checksum file next to the DMG.
//  11. Remove the artifacts this run supersedes.

import Foundation

private let fingerprintHexDigitCount = 40
private let shownIdentityLineCount = 3
private let checksumLengthBytes = 64
private let flagArgumentWidth = 1
private let valuedArgumentWidth = 2
private let buildStampFileName = "build-input-stamp"
private let buildSourceFileName = "build-source-stamp"

/// The channel a direct-download image carries. This path publishes the
/// development build on bob.refineid.fi; the App Store artifact is a different
/// build of the same source, uploaded as a beta or a release candidate. The
/// channel is part of the tag and of the file name, so it cannot be forgotten
/// on the command line and a store image cannot be published here by mistake.
private let releaseChannel = "dev"

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

private func currentBuildNumber() -> String {
  guard let build = xcconfigValue("CURRENT_PROJECT_VERSION") else {
    fail("CURRENT_PROJECT_VERSION not found in \(versionConfigPath().path)")
  }
  return build
}

/// The one tag this checkout may build: the version and build number the
/// configuration defines, on the direct-download channel.
private func expectedTag() -> String {
  "v\(marketingVersion())-\(currentBuildNumber())-\(releaseChannel)"
}

private func dmgFileName(appName: String, tag: String) -> String {
  "\(appName)-\(tag).dmg"
}

/// The identity of the build: the annotated tag it was cut from and the commit
/// that tag names. Both are stamped into the app and carried by the file name,
/// so a published image can be traced to its source without trusting an
/// argument that could disagree with it.
private struct SourceIdentity {
  let tag: String
  let commit: String

  var buildSource: String { "\(tag)@\(commit)" }
}

/// Runs git in the checkout. A git that refuses is an error: a source check
/// that cannot read the repository must stop the run, not pass it.
private func gitOutput(_ arguments: [String]) -> String {
  let result = run("/usr/bin/git", arguments, directory: repositoryRoot)
  if result.failed {
    fail("git \(arguments.joined(separator: " ")) failed:\n\(result.message)")
  }
  return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Confirms the tag really is the build's input: it must point at HEAD, the tree
/// must be clean, and the tag must be annotated. A lightweight tag records no
/// cutter and no message, and can be moved without a trace, so it is refused.
private func sourceIdentity(for tag: String) -> SourceIdentity {
  let commit = gitOutput(["rev-parse", "HEAD"])
  guard commit.count == fingerprintHexDigitCount else {
    fail("could not read HEAD as a commit: \(commit)")
  }

  // Untracked files count: a source file the commit does not contain would be
  // compiled into an image stamped with a tag that cannot reproduce it. Files
  // the repository ignores are not reported, so build output does not refuse
  // the build.
  let dirty = gitOutput(["status", "--porcelain", "--", "."])
  if !dirty.isEmpty {
    fail(
      "the working tree has uncommitted changes or untracked files; an image must"
        + " come from the commit \(tag) names:\n" + dirty
    )
  }

  let atHead = gitOutput(["tag", "--points-at", "HEAD"]).split(separator: "\n").map(String.init)
  guard atHead.contains(tag) else {
    fail(
      "HEAD (\(commit)) does not carry \(tag); tag the commit first:\n"
        + "  git tag -a \(tag) -m 'RefineID \(marketingVersion()) (\(currentBuildNumber()))'\n"
        + "tags at HEAD: \(atHead.isEmpty ? "none" : atHead.joined(separator: ", "))"
    )
  }

  let kind = gitOutput(["cat-file", "-t", "refs/tags/\(tag)"])
  guard kind == "tag" else {
    fail("\(tag) is a \(kind) object, not an annotated tag; annotate it with git tag -a")
  }

  return SourceIdentity(tag: tag, commit: commit)
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
  var releaseTag = ""
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
  case "--tag":
    options.releaseTag = value
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
      "--notary-profile", "--signing-identity", "--tag":
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
  if options.notaryProfile.isEmpty {
    fail("no notarization credential: set --notary-profile (use a notarytool keychain profile)")
  }

  // The tag is checked before any keychain, build or network work, so a wrong
  // source stops the run in the first second instead of after notarization.
  let tag = expectedTag()
  if options.releaseTag.isEmpty {
    fail("--tag is required: a published image names the annotated tag it was built from, \(tag)")
  }
  if options.releaseTag != tag {
    fail("--tag \(options.releaseTag) does not name this build; expected \(tag)")
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

/// The source identity of the cached app. A tag does not change any build
/// input's modification time, so this record, not the input stamp, decides
/// whether a cached app still belongs to the tag being built.
private func recordedBuildSource(derivedData: URL) -> String? {
  let stampFile = derivedData.appendingPathComponent(buildSourceFileName)
  guard let text = try? String(contentsOf: stampFile, encoding: .utf8) else { return nil }
  let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
  return source.isEmpty ? nil : source
}

private func recordBuildSource(_ source: String, derivedData: URL) {
  let stampFile = derivedData.appendingPathComponent(buildSourceFileName)
  do {
    try source.write(to: stampFile, atomically: true, encoding: .utf8)
  } catch {
    fail("could not write \(stampFile.path): \(error.localizedDescription)")
  }
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
  identity: SourceIdentity,
  forceRebuild: Bool
) -> URL {
  let derivedData = repositoryRoot.appendingPathComponent("build/macos-notarized-dmg-deriveddata")
  let products =
    derivedData
    .appendingPathComponent("Build/Products/\(configuration.rawValue)")
    .appendingPathComponent("\(appName).app")

  let cached = FileManager.default.fileExists(atPath: products.path)
  let cachedSource = recordedBuildSource(derivedData: derivedData)
  if cached, !forceRebuild, !cachedAppIsStale(derivedData: derivedData),
    cachedSource == identity.buildSource
  {
    note("using cached \(products.lastPathComponent) built from \(identity.tag)")
    return products
  }
  if cached {
    let reason: String
    if forceRebuild {
      reason = "--force-rebuild"
    } else if cachedSource != identity.buildSource {
      // A new tag moves no file, so the input stamp alone would reuse an app
      // stamped with the previous source.
      reason = "the cached app records \(cachedSource ?? "no source")"
    } else {
      reason = "build input is newer than the cached app"
    }
    note("rebuilding \(appName) (\(reason))")
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
      "REFINEID_BUILD_SOURCE=\(identity.buildSource)",
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
  recordBuildSource(identity.buildSource, derivedData: derivedData)

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
    codesignItem(tokenAppEx, identity: signingIdentity, entitlements: tokenEntitlements)
  }
  if FileManager.default.fileExists(atPath: mainExecutable.path) {
    codesignItem(mainExecutable, identity: signingIdentity, entitlements: appEntitlements)
  }

  // Signing a bundle re-signs its main executable, so the entitlements belong
  // on the bundle as well; signing it without them strips them from the
  // executable, and a sandboxed app without them cannot reach the card.
  codesignItem(app, identity: signingIdentity, entitlements: appEntitlements)

  let verify = run(
    "/usr/bin/codesign",
    ["--verify", "--strict", "--verbose=2", app.path],
    directory: app.deletingLastPathComponent()
  )

  if verify.failed {
    fail("codesign verification failed for \(app.path):\n\(verify.message)")
  }

  // A signature that verifies can still carry no entitlements, so check the
  // ones the app needs to reach the card instead of trusting the verify.
  let requiredEntitlements = [
    (mainExecutable, "com.apple.security.app-sandbox"),
    (tokenExecutable, "com.apple.security.smartcard"),
  ]
  for (path, key) in requiredEntitlements {
    guard FileManager.default.fileExists(atPath: path.path) else { continue }
    let embedded = run(
      "/usr/bin/codesign",
      ["-d", "--entitlements", "-", path.path],
      directory: app.deletingLastPathComponent()
    )
    if !embedded.stdout.contains(key) {
      fail("\(path.lastPathComponent) is signed without \(key)")
    }
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

/// Signs the disk image itself. Gatekeeper assesses a downloaded DMG before it
/// is mounted, and that assessment covers the image, not only the app inside
/// it. The signature must come before notarization: stapling writes the ticket
/// into the image, and signing afterwards replaces the signature and leaves the
/// ticket behind.
private func signDmg(dmg: URL, signingIdentity: String, teamId: String) {
  note("signing \(dmg.lastPathComponent) with Developer ID Application")

  let result = run(
    "/usr/bin/codesign",
    ["--force", "--sign", signingIdentity, "--timestamp", dmg.path],
    directory: dmg.deletingLastPathComponent()
  )
  if result.failed {
    fail("codesign failed for \(dmg.path):\n\(result.message)")
  }

  let verify = run(
    "/usr/bin/codesign",
    ["--verify", "--strict", "--verbose=2", dmg.path],
    directory: dmg.deletingLastPathComponent()
  )
  if verify.failed {
    fail("codesign verification failed for \(dmg.path):\n\(verify.message)")
  }

  // A disk image signed by another team still verifies, and the notary service
  // accepts it, so read back the team that signed this one.
  let details = run(
    "/usr/bin/codesign",
    ["-dv", "--verbose=2", dmg.path],
    directory: dmg.deletingLastPathComponent()
  )
  let expected = "TeamIdentifier=\(teamId)"
  if !details.message.contains(expected) {
    fail("\(dmg.lastPathComponent) is not signed by team \(teamId):\n\(details.message)")
  }

  note("disk image signed and verified")
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

/// Confirms what a user's Mac checks when the image is opened: the signature on
/// the image plus the stapled ticket. Without the image signature this reports
/// `no usable signature` however well the app inside is signed.
private func assessDmg(dmg: URL) {
  note("assessing \(dmg.lastPathComponent) with Gatekeeper")

  let result = run(
    "/usr/sbin/spctl",
    [
      "-a", "-t", "open", "--context", "context:primary-signature", "-vv", dmg.path,
    ],
    directory: dmg.deletingLastPathComponent()
  )

  if result.failed {
    fail("Gatekeeper rejected \(dmg.path):\n\(result.message)")
  }

  note("Gatekeeper accepts \(dmg.lastPathComponent)")
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

/// Removes the artifacts this run supersedes. The output directory is where a
/// person picks the image to publish, so it holds the newest DMG and its
/// checksum only; an older file beside them is the one taken by mistake.
private func pruneSupersededArtifacts(in directory: URL, keeping dmg: URL) {
  let kept: Set<String> = [dmg.lastPathComponent, dmg.lastPathComponent + ".checksums"]
  guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
    fail("could not list \(directory.path)")
  }

  for name in entries.sorted() where name.hasSuffix(".dmg") || name.hasSuffix(".dmg.checksums") {
    guard !kept.contains(name) else { continue }
    let path = directory.appendingPathComponent(name)
    do {
      try FileManager.default.removeItem(at: path)
    } catch {
      fail("could not remove \(path.path): \(error.localizedDescription)")
    }
    note("removed superseded \(name)")
  }
}

private func main() {
  let args = CommandLine.arguments.dropFirst().map { String($0) }
  let options = parseOptions(from: args)
  let identity = sourceIdentity(for: options.releaseTag)
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
    identity: identity,
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

  let dmg = outputDirectory.appendingPathComponent(
    dmgFileName(appName: options.appName, tag: identity.tag)
  )

  createDmg(
    sourceApp: app,
    outputDmg: dmg,
    volumeName: options.appName,
    overwrite: options.overwrite
  )
  signDmg(dmg: dmg, signingIdentity: signingIdentity, teamId: teamId)
  notarizeDmg(dmg: dmg, notaryProfile: options.notaryProfile, notarytool: notarytool)
  stapleDmg(dmg: dmg)
  validateDmg(dmg: dmg)
  assessDmg(dmg: dmg)
  writeChecksumFile(for: dmg)
  pruneSupersededArtifacts(in: outputDirectory, keeping: dmg)

  note("done: \(dmg.path) from \(identity.buildSource)")
}

main()
