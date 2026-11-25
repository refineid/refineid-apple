// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Testing

/// Serializes suites that mutate `DemoMode.shared` or
/// `CredentialRetryHealth.shared`.
///
/// Swift Testing's `.serialized` trait only orders tests within a single
/// suite; separate suites still run concurrently unless they share a
/// cross-suite scoping lock.
internal struct SharedDemoStateScope: SuiteTrait, TestScoping {
  private static let access = SharedSuiteAccess()

  internal var isRecursive: Bool { false }

  internal func scopeProvider(for test: Test, testCase _: Test.Case?) -> Self? {
    test.isSuite ? self : nil
  }

  internal func provideScope(
    for _: Test, testCase _: Test.Case?, performing function: @Sendable () async throws -> Void
  ) async throws {
    try await Self.access.acquire()
    do {
      try await function()
      await Self.access.release()
    } catch {
      await Self.access.release()
      throw error
    }
  }
}
