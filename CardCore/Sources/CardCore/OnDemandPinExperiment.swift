// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Controls the experimental on-demand PIN1 authentication flow.
///
/// In production, contactless Safari signing relies on a previously stored PIN1
/// to complete inside the ~2-second system NFC field without user interruption.
///
/// This experiment evaluates whether Safari client-certificate authentication can
/// instead collect PIN1 on demand via CryptoTokenKit's native secure PIN sheet
/// (`TKTokenPasswordAuthOperation`), then complete authentication across an NFC
/// field renewal without requiring durable PIN1 caching.
///
/// When disabled (the production default), the token extension omits the
/// `signData` password constraint for contactless tokens, and card registration
/// requires PIN1.
///
/// When enabled, the token extension attaches `signDataConstraint` to published
/// contactless keys, prompting CryptoTokenKit for native PIN UI, and allows
/// card priming and registration using CAN alone.
public enum OnDemandPinExperiment: Sendable {
  // MARK: Nested Types

  /// Test isolation override state avoiding optional booleans.
  public enum TestOverride: Sendable {
    case forcedActive
    case forcedInactive
    case unconfigured
  }

  // MARK: Static Properties

  private static let service = "fi.refineid.experiment"
  private static let account = "ondemand-pin1"
  private static let lock = NSLock()
  nonisolated(unsafe) internal static var testOverride: TestOverride = .unconfigured

  // MARK: Static Computed Properties

  /// Whether the on-demand PIN1 experiment is active on this device.
  public static var isEnabled: Bool {
    lock.lock()
    defer { lock.unlock() }
    switch testOverride {
    case .forcedActive:
      return true
    case .forcedInactive:
      return false
    case .unconfigured:
      break
    }
    if TestCredentialEnvironment.isTestMode {
      let value = TestCredentialEnvironment.readCredential(account: account)
      return value == "1"
    }
    var query = query()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data,
      let value = String(data: data, encoding: .utf8)
    else {
      return false
    }
    return value == "1"
  }

  // MARK: Static Functions

  /// Whether this contactless token instance should retain the smart card session
  /// for a cryptographic signing operation.
  ///
  /// App registration fields stay passive to allow the app full control over the card.
  /// When on-demand PIN is active, discovery fields stay passive until PIN1 is ready.
  public static func needsSigningField(
    isRegistrationField: Bool,
    experimentEnabled: Bool = false,
    pinAvailable: Bool = false
  ) -> Bool {
    !isRegistrationField && (!experimentEnabled || pinAvailable)
  }

  /// Native authorization is required for readers and for contactless keys
  /// with on-demand entry enabled and no stored credential.
  public static func requiresPasswordConstraint(
    isContactless: Bool,
    experimentEnabled: Bool,
    hasStoredCredential: Bool
  ) -> Bool {
    !isContactless || (experimentEnabled && !hasStoredCredential)
  }

  /// Sets whether the on-demand PIN1 experiment is active.
  @discardableResult
  public static func setEnabled(_ enabled: Bool) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if !enabled {
      VolatileAcceptedPin1.shared.clearAll()
      TransientCandidatePin1.shared.clearAll()
    }
    if TestCredentialEnvironment.isTestMode {
      TestCredentialEnvironment.writeCredential(enabled ? "1" : "0", account: account)
      return true
    }
    _ = SecItemDelete(query() as CFDictionary)
    var addQuery = query()
    addQuery[kSecValueData as String] = Data((enabled ? "1" : "0").utf8)
    let status = SecItemAdd(addQuery as CFDictionary, nil)
    return status == errSecSuccess
  }

  /// Sets an in-memory override for unit tests.
  public static func setTestOverride(_ overrideState: TestOverride) {
    lock.lock()
    defer { lock.unlock() }
    testOverride = overrideState
    if case .forcedInactive = overrideState {
      VolatileAcceptedPin1.shared.clearAll()
      TransientCandidatePin1.shared.clearAll()
    }
  }

  /// Resets experimental state, deleting any persisted setting and clearing test overrides.
  public static func reset() {
    lock.lock()
    defer { lock.unlock() }
    testOverride = .unconfigured
    VolatileAcceptedPin1.shared.clearAll()
    TransientCandidatePin1.shared.clearAll()
    if TestCredentialEnvironment.isTestMode {
      TestCredentialEnvironment.deleteCredential(account: account)
    } else {
      SecItemDelete(query() as CFDictionary)
    }
  }

  private static func query() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecUseDataProtectionKeychain as String: KeychainPlatform.usesDataProtection,
      kSecAttrSynchronizable as String: false,
    ]
  }
}
