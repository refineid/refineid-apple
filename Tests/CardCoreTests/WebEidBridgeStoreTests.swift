// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// Unit tests for the App Group file-backed Web eID IPC bridge store.
@Suite("Web eID Bridge Store")
internal struct WebEidBridgeStoreTests {
  // MARK: Nested Types

  private enum Fixtures {
    static let staleMarginSeconds: TimeInterval = 60
    static let permissionsMask = 0o777
    static let olderRequestOffsetSeconds: TimeInterval = -10
    static let newerRequestOffsetSeconds: TimeInterval = -2
  }

  // MARK: Static Functions

  private static func makeTempBridgeDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("refineid-webeid-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  // MARK: Functions

  @Test("Bridge writes 0600 files, orders by timestamp, consumes once, and sweeps stale entries")
  internal func bridgeStoreRoundTripAndSweep() throws {
    let tempDir = try Self.makeTempBridgeDirectory()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = WebEidBridgeStore(directory: tempDir)
    let now = Date()
    let older = WebEidBridgeRequest(
      nonce: UUID(),
      createdAt: now.addingTimeInterval(Fixtures.olderRequestOffsetSeconds),
      command: .status
    )
    let newer = WebEidBridgeRequest(
      nonce: UUID(),
      createdAt: now.addingTimeInterval(Fixtures.newerRequestOffsetSeconds),
      command: .status
    )

    #expect(store.writeRequest(newer))
    #expect(store.writeRequest(older))

    let firstFile = tempDir.appendingPathComponent("\(older.nonce.uuidString).request.json")
    let attributes = try FileManager.default.attributesOfItem(atPath: firstFile.path)
    let mode = try #require(attributes[.posixPermissions] as? Int)
    #expect((mode & Fixtures.permissionsMask) == WebEidValues.bridgeFilePermissions)

    #expect(store.takeOldestPendingRequest(now: now) == older)
    #expect(store.takeOldestPendingRequest(now: now) == newer)
    #expect(store.takeOldestPendingRequest(now: now) == nil)

    let response = WebEidBridgeResponse(
      nonce: older.nonce,
      payload: .status(version: WebEidValues.compatibleProtocolVersion)
    )
    #expect(store.writeResponse(response))
    #expect(store.takeResponse(nonce: older.nonce) == response)
    #expect(store.takeResponse(nonce: older.nonce) == nil)

    let stale = WebEidBridgeRequest(nonce: UUID(), createdAt: now, command: .status)
    #expect(store.writeRequest(stale))
    let futureNow = now.addingTimeInterval(
      WebEidValues.staleBridgeFileAgeSeconds + Fixtures.staleMarginSeconds
    )
    store.sweepStaleFiles(now: futureNow)
    #expect(store.takeOldestPendingRequest(now: futureNow) == nil)
  }
}
