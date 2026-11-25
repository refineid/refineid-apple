// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
// https://www.apache.org/licenses/LICENSE-2.0

#if os(macOS)
  import Testing

  /// Serializes suites that change shared test-host fixtures.
  internal struct DssGateFixtureScope: SuiteTrait, TestScoping {
    internal typealias Access = SharedSuiteAccess

    @TaskLocal internal static var hasOwnership = false
    private static let access = Access()

    internal var isRecursive: Bool { false }

    internal func scopeProvider(for test: Test, testCase _: Test.Case?) -> Self? {
      test.isSuite ? self : nil
    }

    internal func provideScope(
      for _: Test, testCase _: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
      try await Self.access.acquire()
      do {
        try await Self.$hasOwnership.withValue(true) {
          try await function()
        }
        await Self.access.release()
      } catch {
        await Self.access.release()
        throw error
      }
    }
  }
#endif
