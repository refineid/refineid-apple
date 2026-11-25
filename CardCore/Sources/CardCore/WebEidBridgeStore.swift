// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Darwin
import Foundation

/// File-backed App Group IPC store bridging `RefineIDSafariExtension` and
/// `RefineID.app` inside macOS App Sandbox.
///
/// Every file is written to an owner-only `0600` temporary file opened with
/// `O_NOFOLLOW`, atomically renamed into place, atomically claimed by rename
/// before decoding, and deleted immediately once consumed.
public struct WebEidBridgeStore: Sendable {
  private static let requestSuffix = ".request.json"
  private static let responseSuffix = ".response.json"
  private static let tempPrefix = ".tmp-"
  private static let claimPrefix = ".claim-"
  private static let readChunkSize = 4_096
  private static let maximumBridgeFileBytes = 262_144

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

  private static func readRegularFileNoFollow(at url: URL) -> Data? {
    let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
    guard descriptor >= 0 else { return nil }
    defer { Darwin.close(descriptor) }
    var fileStat = stat()
    guard Darwin.fstat(descriptor, &fileStat) == 0, (fileStat.st_mode & S_IFMT) == S_IFREG else {
      return nil
    }
    var buffer = [UInt8](repeating: 0, count: Self.readChunkSize)
    var collected = Data()
    while true {
      let count = Darwin.read(descriptor, &buffer, buffer.count)
      if count < 0 {
        return nil
      }
      if count == 0 {
        break
      }
      guard collected.count + count <= Self.maximumBridgeFileBytes else {
        return nil
      }
      collected.append(buffer, count: count)
    }
    return collected
  }

  private static func writeSecureFile(_ data: Data, to tempURL: URL) -> Bool {
    let mode = mode_t(WebEidValues.bridgeFilePermissions)
    let descriptor = Darwin.open(tempURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
    guard descriptor >= 0 else { return false }
    var written = 0
    let succeeded = data.withUnsafeBytes { rawBuffer -> Bool in
      guard let base = rawBuffer.baseAddress else { return data.isEmpty }
      while written < data.count {
        let count = Darwin.write(descriptor, base.advanced(by: written), data.count - written)
        if count <= 0 {
          return false
        }
        written += count
      }
      return true
    }
    let closed = Darwin.close(descriptor) == 0
    if !succeeded || !closed {
      _ = Darwin.unlink(tempURL.path)
      return false
    }
    return true
  }

  /// Writes `request` atomically with `0600` permissions from creation.
  @discardableResult
  public func writeRequest(_ request: WebEidBridgeRequest) -> Bool {
    guard let folder = ensureDirectory() else { return false }
    let fileURL = folder.appendingPathComponent(request.nonce.uuidString + Self.requestSuffix)
    return writeAtomically(request, to: fileURL, in: folder)
  }

  /// Removes an unconsumed or timed-out request file.
  public func removeRequest(nonce: UUID) {
    guard let directory else { return }
    let fileURL = directory.appendingPathComponent(nonce.uuidString + Self.requestSuffix)
    _ = Darwin.unlink(fileURL.path)
  }

  /// Atomically claims and deletes the oldest unexpired pending request, or
  /// returns nil if none wait.
  public func takeOldestPendingRequest(now: Date = Date()) -> WebEidBridgeRequest? {
    sweepStaleFiles(now: now)
    guard let directory else { return nil }
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.creationDateKey],
        options: [.skipsHiddenFiles]
      )) ?? []
    let candidates =
      files
      .filter { $0.lastPathComponent.hasSuffix(Self.requestSuffix) }
      .sorted { lhs, rhs in
        let leftDate =
          (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        let rightDate =
          (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        return leftDate < rightDate
      }

    for candidate in candidates {
      guard let request = claimAndDecodeRequest(at: candidate, in: directory) else { continue }
      if request.expiresAt <= now {
        continue
      }
      return request
    }
    return nil
  }

  /// Writes `response` atomically with `0600` permissions for the extension
  /// handler waiting on `nonce`.
  @discardableResult
  public func writeResponse(_ response: WebEidBridgeResponse) -> Bool {
    guard let folder = ensureDirectory() else { return false }
    let fileURL = folder.appendingPathComponent(response.nonce.uuidString + Self.responseSuffix)
    return writeAtomically(response, to: fileURL, in: folder)
  }

  /// Atomically claims, validates, and deletes the response for `nonce`.
  public func takeResponse(nonce: UUID) -> WebEidBridgeResponse? {
    guard let directory else { return nil }
    let fileURL = directory.appendingPathComponent(nonce.uuidString + Self.responseSuffix)
    let claimURL = directory.appendingPathComponent(Self.claimPrefix + UUID().uuidString)
    guard Darwin.rename(fileURL.path, claimURL.path) == 0 else { return nil }
    defer { _ = Darwin.unlink(claimURL.path) }
    guard
      let data = Self.readRegularFileNoFollow(at: claimURL),
      let response = try? JSONDecoder().decode(WebEidBridgeResponse.self, from: data),
      response.nonce == nonce
    else {
      return nil
    }
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
        options: []
      )) ?? []
    for file in files {
      let modified =
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? .distantPast
      if modified < cutoff {
        _ = Darwin.unlink(file.path)
      }
    }
  }

  private func claimAndDecodeRequest(at url: URL, in folder: URL) -> WebEidBridgeRequest? {
    let expectedName = String(url.lastPathComponent.dropLast(Self.requestSuffix.count))
    guard let expectedNonce = UUID(uuidString: expectedName) else {
      _ = Darwin.unlink(url.path)
      return nil
    }
    let claimURL = folder.appendingPathComponent(Self.claimPrefix + UUID().uuidString)
    guard Darwin.rename(url.path, claimURL.path) == 0 else { return nil }
    defer { _ = Darwin.unlink(claimURL.path) }
    guard
      let data = Self.readRegularFileNoFollow(at: claimURL),
      let request = try? JSONDecoder().decode(WebEidBridgeRequest.self, from: data),
      request.nonce == expectedNonce
    else {
      return nil
    }
    return request
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

  private func writeAtomically<Value: Encodable>(
    _ value: Value,
    to destination: URL,
    in folder: URL
  ) -> Bool {
    guard let data = try? JSONEncoder().encode(value) else { return false }
    let tempURL = folder.appendingPathComponent(Self.tempPrefix + UUID().uuidString)
    guard Self.writeSecureFile(data, to: tempURL) else { return false }
    guard Darwin.rename(tempURL.path, destination.path) == 0 else {
      _ = Darwin.unlink(tempURL.path)
      return false
    }
    return true
  }
}
