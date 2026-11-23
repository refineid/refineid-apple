// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import Foundation
  import ObjectiveC

  @testable import CardCore

  /// Installs the forwarding getter once and activates it only in the fixture task.
  ///
  /// The native getter stays forwarded for the test host lifetime; outside the
  /// task-local scope it returns an unmodified ephemeral configuration.
  ///
  /// Because `isFixtureActive` is a `@TaskLocal`, activation propagates across
  /// structured child tasks (`async let`, `withThrowingTaskGroup`) and does not
  /// cross `Task.detached` or `DispatchQueue`. Verified production call paths
  /// that construct `URLSessionConfiguration.ephemeral` via
  /// `SigningNetwork.validatedSessionConfiguration(validating:)`:
  /// - `TimestampClient.token(over:)` / `TimestampClient.probe(_:)` ->
  ///   `SigningNetwork.post` -> `SigningNetwork.firstAnswer` (`withThrowingTaskGroup`)
  /// - `DocumentSigner.longTerm` and `AsicSigner.evidenced` ->
  ///   `ValidationMaterialCollector` -> `SigningNetwork.get` / `.post` ->
  ///   `SigningNetwork.firstAnswer` (`withThrowingTaskGroup`)
  /// None of these signing paths dispatch through `Task.detached` or `DispatchQueue`.
  internal enum DssGateSessionHook {
    private enum Failure: Error {
      case missingFixtureOwnership
      case unavailableSessionConfiguration
    }

    @TaskLocal internal static var isFixtureActive = false
    nonisolated(unsafe) private static var isInstalled = false

    private static func install() throws {
      guard !isInstalled else { return }
      guard
        let original = class_getClassMethod(
          URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.ephemeral)),
        let replacement = class_getClassMethod(
          URLSessionConfiguration.self, #selector(URLSessionConfiguration.dssGateEphemeral))
      else { throw Failure.unavailableSessionConfiguration }
      method_exchangeImplementations(original, replacement)
      isInstalled = true
    }

    internal static func withFixture(
      authorities: DssGateAuthorities, performing operation: () async throws -> Void
    ) async throws {
      guard DssGateFixtureScope.hasOwnership else { throw Failure.missingFixtureOwnership }
      try install()
      DssGateUrlProtocol.authorities = authorities
      DssGateUrlProtocol.timestampAuthorities = nil
      DssGateUrlProtocol.resetInterceptedAddresses()
      TrustRootsCache.shared.reset()
      TrustRootsCache.shared.register(authorities.caCertificate)
      defer {
        DssGateUrlProtocol.authorities = nil
        DssGateUrlProtocol.timestampAuthorities = nil
        DssGateUrlProtocol.resetInterceptedAddresses()
        TrustRootsCache.shared.reset()
      }
      try await $isFixtureActive.withValue(true) {
        try await operation()
      }
    }
  }

#endif
