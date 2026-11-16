// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  import Foundation
  import RappEngine
  import Security
  import Testing

  @testable import CardCore

  /// Verifies symlink-directory rejection, squatter socket reclamation, and inode-checked listener stop.
  @Suite
  internal struct RappHeldSessionTransportTests {
    /// Synthetic 16-byte pair identifier.
    private static let pairID = Data("pair-identifier!".utf8)

    /// Synthetic client-authentication digest.
    private static let digest = Data("auth-digest".utf8)

    /// Synthetic signature answer bytes.
    private static let signatureBytes = Data("signed-digest".utf8)

    /// Creates a short-path temporary socket URL within `sockaddr_un.sun_path` bounds.
    private static func temporarySocketURL() -> (directory: URL, socket: URL) {
      let suffix = String(UUID().uuidString.prefix(8))
      let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("rh-\(suffix)", isDirectory: true)
      let socket = directory.appendingPathComponent("s", isDirectory: false)
      return (directory, socket)
    }

    /// Builds an identifier-pinned policy matching the running test host process.
    private static func hostPolicy() throws -> RappHeldSessionHandoff.PeerPolicy {
      let selfIdentity = try #require(RappHeldSessionHandoff.currentProcessSigningIdentity())
      return try #require(
        RappHeldSessionHandoff.identifierPeerPolicy(
          signingIdentifier: selfIdentity.identifier,
          requiredStaticFlags: [],
          forbiddenStaticFlags: [],
          requiredDynamicStatus: .valid,
          forbiddenDynamicStatus: []
        )
      )
    }

    /// Listener refuses to bind inside a directory path that was replaced with a symbolic link.
    @Test
    internal func listenerRejectsSymlinkedSocketDirectory() throws {
      let policy = try Self.hostPolicy()
      let paths = Self.temporarySocketURL()
      let targetPaths = Self.temporarySocketURL()
      defer {
        try? FileManager.default.removeItem(at: paths.directory)
        try? FileManager.default.removeItem(at: targetPaths.directory)
      }
      try FileManager.default.createDirectory(
        at: targetPaths.directory,
        withIntermediateDirectories: true
      )
      try FileManager.default.createSymbolicLink(
        at: paths.directory,
        withDestinationURL: targetPaths.directory
      )
      let listener = RappHeldSessionHandoff.startListener(
        socketURL: paths.socket,
        clientPolicy: policy,
        serverPolicy: policy
      ) { _ in .failed(.protocolFailure) }
      #expect(listener == nil)
    }

    /// Listener preserves verified owners, reclaims unverified squatters, and guards `stop()` by inode.
    @Test
    internal func listenerReclaimsSquatterAndGuardsStopInode() throws {
      let hostPolicy = try Self.hostPolicy()
      let distinctServerPolicy = try #require(
        RappHeldSessionHandoff.identifierPeerPolicy(
          signingIdentifier: RappHeldSessionHandoff.appSigningIdentifier,
          requiredStaticFlags: [],
          forbiddenStaticFlags: [],
          requiredDynamicStatus: .valid,
          forbiddenDynamicStatus: []
        )
      )
      let paths = Self.temporarySocketURL()
      defer { try? FileManager.default.removeItem(at: paths.directory) }

      let primary = try #require(
        RappHeldSessionHandoff.startListener(
          socketURL: paths.socket,
          clientPolicy: hostPolicy,
          serverPolicy: hostPolicy
        ) { _ in .response(.signature(Self.signatureBytes)) }
      )
      #expect(
        RappHeldSessionHandoff.startListener(
          socketURL: paths.socket,
          clientPolicy: hostPolicy,
          serverPolicy: hostPolicy
        ) { _ in .failed(.protocolFailure) } == nil
      )
      let reclaimed = try #require(
        RappHeldSessionHandoff.startListener(
          socketURL: paths.socket,
          clientPolicy: hostPolicy,
          serverPolicy: distinctServerPolicy
        ) { _ in .response(.authenticationCertificate(Self.signatureBytes)) }
      )
      defer { reclaimed.stop() }
      primary.stop()

      let request = try #require(
        RappHeldSessionHandoff.Request(
          pairID: Self.pairID,
          keyProfile: .ecdsaP256,
          algorithm: .ecdsaSHA256,
          digest: Self.digest
        )
      )
      let answer = RappHeldSessionHandoff.ask(
        request,
        socketURL: paths.socket,
        serverPolicy: hostPolicy
      )
      #expect(answer == .response(.authenticationCertificate(Self.signatureBytes)))
    }
  }
#endif
