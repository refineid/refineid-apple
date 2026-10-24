// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Ephemeral in-memory store active during testing or virtual card execution.
///
/// Prevents test executions and automation runners from touching the host
/// system's persistent login keychain or triggering macOS Security Agent prompts.
///
/// The store, its predicate and every branch that selects it exist only when
/// CardCore is compiled with `DEBUG`. Otherwise the type carries `isTestMode`
/// alone, constant `false`, so app code compiled with `DEBUG` against a
/// non-`DEBUG` CardCore still builds and the keychain is the only store.
public enum TestCredentialEnvironment {
  #if DEBUG
    /// Launch arguments that select test isolation, each matched as a whole
    /// argument: the UI-test and the virtual-card launches of the app.
    private static let launchArguments = ["--ui-test", "--virtual-card"]

    /// The environment key the test runner sets for every process it hosts.
    private static let runnerEnvironmentKey = "XCTestConfigurationFilePath"

    /// Whether test isolation mode is active.
    public static let isTestMode = selectsTestMode(
      arguments: ProcessInfo.processInfo.arguments,
      environment: ProcessInfo.processInfo.environment)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var credentials: [String: String] = [:]
    nonisolated(unsafe) private static var primedIdentities: [String: Data] = [:]

    nonisolated(unsafe) private static var trustedCas: [String: Data] = [:]
  #else
    /// Whether test isolation mode is active: never, without `DEBUG`.
    public static let isTestMode = false
  #endif

  #if DEBUG
    /// Whether a launch with these arguments and this environment selects
    /// test isolation: a whole launch argument or the runner's key, never a
    /// substring.
    internal static func selectsTestMode(
      arguments: [String],
      environment: [String: String]
    ) -> Bool {
      launchArguments.contains(where: arguments.contains)
        || environment[runnerEnvironmentKey] != nil
    }

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
  #endif
}
