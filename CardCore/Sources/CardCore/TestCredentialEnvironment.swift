// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Ephemeral in-memory store active during testing or virtual card execution.
///
/// Prevents test executions and automation runners from touching the host
/// system's persistent login keychain or triggering macOS Security Agent prompts.
public enum TestCredentialEnvironment {
  /// Whether test isolation mode is active.
  public static let isTestMode: Bool = {
    ProcessInfo.processInfo.arguments.contains("--ui-test")
      || ProcessInfo.processInfo.arguments.contains("--virtual-card")
      || ProcessInfo.processInfo.arguments.contains("-XCTest")
      || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
      || ProcessInfo.processInfo.environment["XCInjectBundleInto"] != nil
  }()

  private static let lock = NSLock()
  nonisolated(unsafe) private static var credentials: [String: String] = [:]
  nonisolated(unsafe) private static var primedIdentities: [String: Data] = [:]

  nonisolated(unsafe) private static var trustedCas: [String: Data] = [:]

  internal static func credentialExists(account: String) -> Bool {
    lock.withLock { credentials[account] != nil }
  }

  internal static func readCredential(account: String) -> String? {
    lock.withLock { credentials[account] }
  }

  internal static func writeCredential(_ value: String, account: String) {
    lock.withLock { credentials[account] = value }
  }

  internal static func deleteCredential(account: String) {
    _ = lock.withLock { credentials.removeValue(forKey: account) }
  }

  internal static func credentialAccounts(prefix: String, suffix: String) -> [String] {
    lock.withLock {
      credentials.keys.filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }.sorted()
    }
  }

  internal static func readPrime(account: String) -> Data? {
    lock.withLock { primedIdentities[account] }
  }

  internal static func storePrime(_ payload: Data, account: String) {
    lock.withLock { primedIdentities[account] = payload }
  }

  internal static func deletePrime(account: String) {
    _ = lock.withLock { primedIdentities.removeValue(forKey: account) }
  }

  internal static func allPrimes() -> [(account: String, data: Data)] {
    lock.withLock { primedIdentities.map { ($0.key, $0.value) } }
  }

  internal static func forgetAllPrimes() {
    lock.withLock { primedIdentities.removeAll() }
  }

  internal static func readTrustedCa(account: String) -> Data? {
    lock.withLock { trustedCas[account] }
  }

  internal static func storeTrustedCa(_ payload: Data, account: String) {
    lock.withLock { trustedCas[account] = payload }
  }

  internal static func deleteTrustedCa(account: String) {
    _ = lock.withLock { trustedCas.removeValue(forKey: account) }
  }

  internal static func allTrustedCas() -> [(account: String, data: Data)] {
    lock.withLock { trustedCas.map { ($0.key, $0.value) } }
  }

  internal static func forgetAllTrustedCas() {
    lock.withLock { trustedCas.removeAll() }
  }
}
