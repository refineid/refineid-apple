// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine) && os(macOS)
  import Darwin
  import Foundation
  import Security

  /// Kernel `audit_token_t` peer code-signing verification for local handoff sockets.
  extension RappHeldSessionHandoff {
    /// Code-signing identifier, optional Team ID, and flags read from the current process.
    internal struct SigningIdentity: Sendable, Equatable {
      /// The code-signing `CFBundleIdentifier` / `kSecCodeInfoIdentifier`.
      internal let identifier: String

      /// The Apple Developer Team Identifier (`kSecCodeInfoTeamIdentifier`), nil on ad-hoc builds.
      internal let teamIdentifier: String?

      /// Embedded `CodeDirectory` signature flags (`kSecCodeInfoFlags`).
      internal let signatureFlags: UInt32

      /// Live kernel code-signing status word (`kSecCodeInfoStatus`).
      internal let dynamicStatus: UInt32
    }

    /// Static and dynamic code-signing policy enforced on a connected socket peer.
    internal struct PeerPolicy: @unchecked Sendable {
      /// Compiled Security framework code-signing requirement.
      internal let requirement: SecRequirement

      /// Static `CodeDirectory` flags that must all be present on the peer signature.
      internal let requiredStaticFlags: SecCodeSignatureFlags

      /// Static `CodeDirectory` flags that must all be absent from the peer signature.
      internal let forbiddenStaticFlags: SecCodeSignatureFlags

      /// Dynamic kernel status flags that must all be active on the live peer process.
      internal let requiredDynamicStatus: SecCodeStatus

      /// Dynamic kernel status flags that must all be absent on the live peer process.
      internal let forbiddenDynamicStatus: SecCodeStatus
    }

    /// Reads the current running process's code-signing identity and live status flags.
    internal static func currentProcessSigningIdentity() -> SigningIdentity? {
      var selfCode: SecCode?
      guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode else {
        return nil
      }
      let info = copyCodeInformation(of: selfCode)
      guard
        let identifier = info[kSecCodeInfoIdentifier as String] as? String,
        let rawFlags = info[kSecCodeInfoFlags as String] as? UInt32,
        let rawStatus = info[kSecCodeInfoStatus as String] as? UInt32,
        isSafeRequirementToken(identifier)
      else {
        return nil
      }
      let rawTeam = info[kSecCodeInfoTeamIdentifier as String] as? String
      if let rawTeam, !isSafeRequirementToken(rawTeam) {
        return nil
      }
      return SigningIdentity(
        identifier: identifier,
        teamIdentifier: rawTeam,
        signatureFlags: rawFlags,
        dynamicStatus: rawStatus
      )
    }

    /// Builds the production policy requiring Apple anchor, Team ID, Hardened Runtime, and un-debugged state.
    internal static func productionPeerPolicy(
      expectedSigningIdentifier: String
    ) -> PeerPolicy? {
      guard
        let selfIdentity = currentProcessSigningIdentity(),
        let teamIdentifier = selfIdentity.teamIdentifier,
        let requirement = peerRequirement(
          signingIdentifier: expectedSigningIdentifier,
          teamIdentifier: teamIdentifier
        )
      else {
        return nil
      }
      return PeerPolicy(
        requirement: requirement,
        requiredStaticFlags: .runtime,
        forbiddenStaticFlags: .adhoc,
        requiredDynamicStatus: [.valid, .hard, .kill],
        forbiddenDynamicStatus: .debugged
      )
    }

    /// Verifies that the connected `AF_UNIX` peer satisfies `policy` via kernel `LOCAL_PEERTOKEN`.
    internal static func verifyPeer(
      of socketDescriptor: Int32,
      satisfying policy: PeerPolicy?
    ) -> Bool {
      guard
        let policy,
        let tokenData = peerAuditToken(of: socketDescriptor)
      else {
        return false
      }
      var guestCode: SecCode?
      let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary
      guard
        SecCodeCopyGuestWithAttributes(nil, attributes, [], &guestCode) == errSecSuccess,
        let guestCode,
        SecCodeCheckValidity(guestCode, [], policy.requirement) == errSecSuccess
      else {
        return false
      }
      return peerFlagsAndStatusMatch(guestCode: guestCode, policy: policy)
    }

    /// Compiles an Apple-anchored code-signing requirement pinning signing ID and Team ID.
    internal static func peerRequirement(
      signingIdentifier: String,
      teamIdentifier: String
    ) -> SecRequirement? {
      guard
        isSafeRequirementToken(signingIdentifier),
        isSafeRequirementToken(teamIdentifier)
      else {
        return nil
      }
      let expression =
        "anchor apple generic"
        + " and identifier \"\(signingIdentifier)\""
        + " and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
      var requirement: SecRequirement?
      guard
        SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess
      else {
        return nil
      }
      return requirement
    }

    /// Compiles an identifier-pinned peer policy for test harnesses running under ad-hoc test hosts.
    internal static func identifierPeerPolicy(
      signingIdentifier: String,
      requiredStaticFlags: SecCodeSignatureFlags,
      forbiddenStaticFlags: SecCodeSignatureFlags,
      requiredDynamicStatus: SecCodeStatus,
      forbiddenDynamicStatus: SecCodeStatus
    ) -> PeerPolicy? {
      guard isSafeRequirementToken(signingIdentifier) else { return nil }
      let expression = "identifier \"\(signingIdentifier)\""
      var requirement: SecRequirement?
      guard
        SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
        let requirement
      else {
        return nil
      }
      return PeerPolicy(
        requirement: requirement,
        requiredStaticFlags: requiredStaticFlags,
        forbiddenStaticFlags: forbiddenStaticFlags,
        requiredDynamicStatus: requiredDynamicStatus,
        forbiddenDynamicStatus: forbiddenDynamicStatus
      )
    }

    /// Queries both static signing metadata and live dynamic kernel status for a `SecCode` handle.
    private static func copyCodeInformation(of code: SecCode) -> [String: Any] {
      // SecCodeCopySigningInformation accepts a live SecCodeRef directly when
      // kSecCSDynamicInformation is requested (SecCode.h:350-353).
      let codeReference = unsafeBitCast(code, to: SecStaticCode.self)
      let flags = SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSDynamicInformation)
      var rawInfo: CFDictionary?
      guard SecCodeCopySigningInformation(codeReference, flags, &rawInfo) == errSecSuccess else {
        return [:]
      }
      return rawInfo as? [String: Any] ?? [:]
    }

    /// Checks static `CodeDirectory` flags and live kernel `SecCodeStatus` of `guestCode`.
    private static func peerFlagsAndStatusMatch(
      guestCode: SecCode,
      policy: PeerPolicy
    ) -> Bool {
      let info = copyCodeInformation(of: guestCode)
      guard
        let rawFlags = info[kSecCodeInfoFlags as String] as? UInt32,
        let rawStatus = info[kSecCodeInfoStatus as String] as? UInt32
      else {
        return false
      }
      let staticFlags = SecCodeSignatureFlags(rawValue: rawFlags)
      let dynamicStatus = SecCodeStatus(rawValue: rawStatus)
      return staticFlags.isSuperset(of: policy.requiredStaticFlags)
        && staticFlags.isDisjoint(with: policy.forbiddenStaticFlags)
        && dynamicStatus.isSuperset(of: policy.requiredDynamicStatus)
        && dynamicStatus.isDisjoint(with: policy.forbiddenDynamicStatus)
    }

    /// Retrieves the connected peer's kernel `audit_token_t` via `LOCAL_PEERTOKEN`.
    private static func peerAuditToken(of socketDescriptor: Int32) -> Data? {
      var token = audit_token_t()
      var length = socklen_t(MemoryLayout<audit_token_t>.size)
      let status = withUnsafeMutablePointer(to: &token) { pointer in
        getsockopt(socketDescriptor, SOL_LOCAL, LOCAL_PEERTOKEN, pointer, &length)
      }
      guard status == 0, length == socklen_t(MemoryLayout<audit_token_t>.size) else {
        return nil
      }
      return withUnsafeBytes(of: &token) { Data($0) }
    }

    /// Restricts requirement tokens to safe ASCII identifier characters.
    private static func isSafeRequirementToken(_ value: String) -> Bool {
      guard !value.isEmpty else { return false }
      return value.utf8.allSatisfy { byte in
        (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
          || (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
          || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
          || byte == UInt8(ascii: ".")
          || byte == UInt8(ascii: "-")
          || byte == UInt8(ascii: "_")
      }
    }
  }
#endif
