// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// File-backed App Group IPC store bridging `RefineIDSafariExtension` and
/// `RefineID.app` inside macOS App Sandbox.
///
/// Every file is written atomically with `0600` permissions inside a `0700`
/// directory and deleted immediately once consumed.
public struct WebEidBridgeStore: Sendable {
  private static let requestSuffix = ".request.json"
  private static let responseSuffix = ".response.json"

  /// Shared production store backed by `group.fi.refineid.RefineID`.
  public static let shared = Self(directory: Self.defaultAppGroupDirectory())

  /// Directory where request and response files live, or nil if unavailable.
  public let directory: URL?

  /// Creates a bridge store backed by `directory`.
  public init(directory: URL?) {
    self.directory = directory
  }

  private static func defaultAppGroupDirectory() -> URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: WebEidValues.appGroupIdentifier)?
      .appendingPathComponent(WebEidValues.bridgeDirectoryName, isDirectory: true)
  }

  /// Writes `request` atomically and restricts file permissions to owner-only.
  @discardableResult
  public func writeRequest(_ request: WebEidBridgeRequest) -> Bool {
    guard let folder = ensureDirectory() else { return false }
    let fileURL = folder.appendingPathComponent(request.nonce.uuidString + Self.requestSuffix)
    return writeAtomically(request, to: fileURL)
  }

  /// Removes an unconsumed or timed-out request file.
  public func removeRequest(nonce: UUID) {
    guard let directory else { return }
    let fileURL = directory.appendingPathComponent(nonce.uuidString + Self.requestSuffix)
    try? FileManager.default.removeItem(at: fileURL)
  }

  /// Claims and deletes the oldest pending request, or returns nil if none wait.
  public func takeOldestPendingRequest(now: Date = Date()) -> WebEidBridgeRequest? {
    sweepStaleFiles(now: now)
    guard let directory else { return nil }
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.creationDateKey],
        options: [.skipsHiddenFiles]
      )) ?? []
    let requestFiles = files.filter { $0.lastPathComponent.hasSuffix(Self.requestSuffix) }
    var decoded: [(url: URL, request: WebEidBridgeRequest)] = []
    for url in requestFiles {
      if let data = try? Data(contentsOf: url),
        let request = try? JSONDecoder().decode(WebEidBridgeRequest.self, from: data)
      {
        decoded.append((url: url, request: request))
      } else {
        try? FileManager.default.removeItem(at: url)
      }
    }
    guard let oldest = decoded.min(by: { $0.request.createdAt < $1.request.createdAt }) else {
      return nil
    }
    try? FileManager.default.removeItem(at: oldest.url)
    return oldest.request
  }

  /// Writes `response` atomically for the extension handler waiting on `nonce`.
  @discardableResult
  public func writeResponse(_ response: WebEidBridgeResponse) -> Bool {
    guard let folder = ensureDirectory() else { return false }
    let fileURL = folder.appendingPathComponent(response.nonce.uuidString + Self.responseSuffix)
    return writeAtomically(response, to: fileURL)
  }

  /// Reads and deletes the response for `nonce`, or returns nil if still pending.
  public func takeResponse(nonce: UUID) -> WebEidBridgeResponse? {
    guard let directory else { return nil }
    let fileURL = directory.appendingPathComponent(nonce.uuidString + Self.responseSuffix)
    guard
      let data = try? Data(contentsOf: fileURL),
      let response = try? JSONDecoder().decode(WebEidBridgeResponse.self, from: data)
    else {
      return nil
    }
    try? FileManager.default.removeItem(at: fileURL)
    return response
  }

  /// Deletes orphaned request or response files older than the stale cutoff.
  public func sweepStaleFiles(now: Date = Date()) {
    guard let directory else { return }
    let cutoff = now.addingTimeInterval(-WebEidValues.staleBridgeFileAgeSeconds)
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )) ?? []
    for file in files {
      let modified =
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? .distantPast
      if modified < cutoff {
        try? FileManager.default.removeItem(at: file)
      }
    }
  }

  private func ensureDirectory() -> URL? {
    guard let directory else { return nil }
    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: WebEidValues.bridgeDirectoryPermissions]
      )
      return directory
    } catch {
      return nil
    }
  }

  private func writeAtomically<Value: Encodable>(_ value: Value, to url: URL) -> Bool {
    guard let data = try? JSONEncoder().encode(value) else { return false }
    do {
      try data.write(to: url, options: .atomic)
      try FileManager.default.setAttributes(
        [.posixPermissions: WebEidValues.bridgeFilePermissions],
        ofItemAtPath: url.path
      )
      return true
    } catch {
      return false
    }
  }
}
