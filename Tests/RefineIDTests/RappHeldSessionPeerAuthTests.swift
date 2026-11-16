// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)
  import Foundation
  import os
  import RappEngine
  import Security
  import Testing

  @testable import CardCore

  /// Verifies bidirectional kernel `audit_token_t` code-signing authentication on handoff sockets.
  @Suite
  internal struct RappHeldSessionPeerAuthTests {
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

    /// Builds a valid handoff request fixture.
    private static func sampleRequest() throws -> RappHeldSessionHandoff.Request {
      try #require(
        RappHeldSessionHandoff.Request(
          pairID: pairID,
          keyProfile: .ecdsaP256,
          algorithm: .ecdsaSHA256,
          digest: digest
        )
      )
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

    /// Requirement compiler sanitizes tokens and `normalizedTimeval` carries microsecond rounding.
    @Test
    internal func peerRequirementSanitizationAndTimevalNormalization() {
      #expect(
        RappHeldSessionHandoff.peerRequirement(
          signingIdentifier: "fi.refineid.ReFineID",
          teamIdentifier: "TEAM123456"
        ) != nil
      )
      for unsafe in ["", "fi.refineid\" or true", "TEAM 123", "id;drop", "id/slash"] {
        #expect(
          RappHeldSessionHandoff.peerRequirement(
            signingIdentifier: unsafe,
            teamIdentifier: "TEAM123456"
          ) == nil
        )
        #expect(
          RappHeldSessionHandoff.peerRequirement(
            signingIdentifier: "fi.refineid.ReFineID",
            teamIdentifier: unsafe
          ) == nil
        )
      }
      let nearCarry = RappHeldSessionHandoff.normalizedTimeval(seconds: 1.9999999)
      #expect(nearCarry.tv_sec == 2)
      #expect(nearCarry.tv_usec == 0)
    }

    /// Ad-hoc processes without an Apple Team ID fail closed when requesting a production policy.
    @Test
    internal func productionPolicyFailsClosedWithoutAppleTeamIdentifier() throws {
      let selfIdentity = try #require(RappHeldSessionHandoff.currentProcessSigningIdentity())
      let policy = RappHeldSessionHandoff.productionPeerPolicy(
        expectedSigningIdentifier: RappHeldSessionHandoff.appSigningIdentifier
      )
      #expect((policy != nil) == (selfIdentity.teamIdentifier != nil))
    }

    /// Matching kernel `audit_token_t` code-signing policies complete a full handoff round-trip.
    @Test
    internal func verifiedPeerRoundTripsRequestAndAnswer() throws {
      let policy = try Self.hostPolicy()
      let paths = Self.temporarySocketURL()
      defer { try? FileManager.default.removeItem(at: paths.directory) }
      let request = try Self.sampleRequest()

      let listener = try #require(
        RappHeldSessionHandoff.startListener(
          socketURL: paths.socket,
          clientPolicy: policy,
          serverPolicy: policy
        ) { received in
          guard received == request else { return .failed(.protocolFailure) }
          return .response(.signature(Self.signatureBytes))
        }
      )
      defer { listener.stop() }

      let answer = RappHeldSessionHandoff.ask(
        request,
        socketURL: paths.socket,
        serverPolicy: policy
      )
      #expect(answer == .response(.signature(Self.signatureBytes)))
    }

    /// Client rejects a socket listener whose audit token fails server verification before sending bytes.
    @Test
    internal func clientRejectsUnverifiedSquatterListenerAndReturnsNilForFallback() throws {
      let policy = try Self.hostPolicy()
      let untrustedServerPolicy = try #require(
        RappHeldSessionHandoff.identifierPeerPolicy(
          signingIdentifier: "fi.refineid.ReFineID.untrusted-squatter",
          requiredStaticFlags: [],
          forbiddenStaticFlags: [],
          requiredDynamicStatus: .valid,
          forbiddenDynamicStatus: []
        )
      )
      let paths = Self.temporarySocketURL()
      defer { try? FileManager.default.removeItem(at: paths.directory) }
      let request = try Self.sampleRequest()
      let handlerInvoked = OSAllocatedUnfairLock(initialState: false)

      let listener = try #require(
        RappHeldSessionHandoff.startListener(
          socketURL: paths.socket,
          clientPolicy: policy,
          serverPolicy: policy
        ) { _ in
          handlerInvoked.withLock { $0 = true }
          return .failed(.protocolFailure)
        }
      )
      defer { listener.stop() }

      let answer = RappHeldSessionHandoff.ask(
        request,
        socketURL: paths.socket,
        serverPolicy: untrustedServerPolicy
      )
      #expect(answer == nil)
      #expect(!handlerInvoked.withLock { $0 })
    }

    /// Server rejects an unauthorized caller without invoking the handler; verified server close fails closed.
    @Test
    internal func serverRejectsUnauthorizedCallerBeforeInvokingHandler() throws {
      let hostPolicy = try Self.hostPolicy()
      let extensionClientPolicy = try #require(
        RappHeldSessionHandoff.identifierPeerPolicy(
          signingIdentifier: RappHeldSessionHandoff.tokenExtensionSigningIdentifier,
          requiredStaticFlags: [],
          forbiddenStaticFlags: [],
          requiredDynamicStatus: .valid,
          forbiddenDynamicStatus: []
        )
      )
      let paths = Self.temporarySocketURL()
      defer { try? FileManager.default.removeItem(at: paths.directory) }
      let request = try Self.sampleRequest()
      let handlerInvoked = OSAllocatedUnfairLock(initialState: false)

      let listener = try #require(
        RappHeldSessionHandoff.startListener(
          socketURL: paths.socket,
          clientPolicy: extensionClientPolicy,
          serverPolicy: hostPolicy
        ) { _ in
          handlerInvoked.withLock { $0 = true }
          return .response(.signature(Self.signatureBytes))
        }
      )
      defer { listener.stop() }

      let answer = RappHeldSessionHandoff.ask(
        request,
        socketURL: paths.socket,
        serverPolicy: hostPolicy
      )
      #expect(answer == .failed(.transport))
      #expect(!handlerInvoked.withLock { $0 })
    }

    /// Static and dynamic code-signing flag checks reject ad-hoc or non-Hardened-Runtime peers.
    @Test
    internal func signatureAndDynamicStatusPoliciesRejectDisallowedPeers() throws {
      let selfIdentity = try #require(RappHeldSessionHandoff.currentProcessSigningIdentity())
      let hostFlags = SecCodeSignatureFlags(rawValue: selfIdentity.signatureFlags)
      guard hostFlags.contains(.adhoc) || !hostFlags.contains(.runtime) else { return }
      let hostPolicy = try Self.hostPolicy()
      let hardenedPolicy = try #require(
        RappHeldSessionHandoff.identifierPeerPolicy(
          signingIdentifier: selfIdentity.identifier,
          requiredStaticFlags: .runtime,
          forbiddenStaticFlags: .adhoc,
          requiredDynamicStatus: [.valid, .hard, .kill],
          forbiddenDynamicStatus: .debugged
        )
      )
      let paths = Self.temporarySocketURL()
      defer { try? FileManager.default.removeItem(at: paths.directory) }
      let request = try Self.sampleRequest()

      let listener = try #require(
        RappHeldSessionHandoff.startListener(
          socketURL: paths.socket,
          clientPolicy: hardenedPolicy,
          serverPolicy: hostPolicy
        ) { _ in
          .response(.signature(Self.signatureBytes))
        }
      )
      defer { listener.stop() }

      let answer = RappHeldSessionHandoff.ask(
        request,
        socketURL: paths.socket,
        serverPolicy: hostPolicy
      )
      #expect(answer == .failed(.transport))
    }
  }
#endif
