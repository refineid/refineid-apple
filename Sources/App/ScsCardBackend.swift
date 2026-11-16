// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_SCS
  import CardCore
  import CryptoKit
  import Foundation
  import os
  import Security

  /// The production SCS signing backend: one card session per
  /// operation, serial-bound leaf caching, per-origin prompt rate
  /// limiting, the retry floor before any credential, and a prompt
  /// naming the live cardholder and SHA-256 fingerprint.
  internal final class ScsCardBackend: ScsSigningBackend, Sendable {
    private final class Box<Value: Sendable>: @unchecked Sendable {
      var value: Value

      init(_ value: Value) {
        self.value = value
      }
    }

    internal static let readTimeoutSeconds: Double = 15
    internal static let signTimeoutSeconds: Double = 125

    internal let leafCache = OSAllocatedUnfairLock(initialState: ScsLeafCache())
    internal let rateLimiter = ScsPromptRateLimiter()
    private let activeCancellation = OSAllocatedUnfairLock<ScsPromptCancellationToken?>(
      initialState: nil)

    private static func computeDigest(of data: Data, hash: SigningHash) -> Data? {
      switch hash {
      case .sha256:
        Data(SHA256.hash(data: data))
      case .sha384:
        Data(SHA384.hash(data: data))
      case .sha512:
        Data(SHA512.hash(data: data))
      case .sha1, .sha224:
        nil
      }
    }

    /// Installs `token` for the active `signQueue` execution and clears
    /// it on exit.
    internal func withCancellation<Answer>(
      _ token: ScsPromptCancellationToken,
      _ body: () -> Answer
    ) -> Answer {
      activeCancellation.withLock { $0 = token }
      defer { activeCancellation.withLock { $0 = nil } }
      return body()
    }

    /// Clears cached card leaves and prompt rate-limit buckets on
    /// server stop.
    internal func resetSessionState() {
      leafCache.withLock { $0.invalidate() }
      rateLimiter.reset()
    }

    internal func certificateChain(for purpose: ScsSignPurpose) -> [Data] {
      guard let leaf = currentLeaf(for: purpose) else { return [] }
      return [leaf]
    }

    internal func keyAlgorithm(for purpose: ScsSignPurpose) -> ScsKeyAlgorithm {
      guard
        let leaf = currentLeaf(for: purpose),
        let cert = SecCertificateCreateWithData(nil, leaf as CFData),
        let profile = CardKeyProfile.resolve(fromCertificate: cert)
      else {
        return .rsa
      }
      return switch profile {
      case .ecdsaP256, .ecdsaP384:
        .ecdsa
      case .rsa2048, .rsa3072:
        .rsa
      }
    }

    internal func sign(_ request: ScsSignRequest) throws -> Data {
      guard let digest = Self.computeDigest(of: request.data, hash: request.hash) else {
        throw ScsBackendFailure.signingUnavailable("unsupported digest")
      }
      let cancellation = activeCancellation.withLock { $0 } ?? ScsPromptCancellationToken()
      let outcome: Result<Data, ScsBackendFailure>? = withCard(
        timeoutSeconds: Self.signTimeoutSeconds
      ) { [self] operations in
        performSign(
          operations,
          request: request,
          digest: digest,
          cancellation: cancellation
        )
      }
      guard let outcome else {
        leafCache.withLock { $0.invalidate() }
        throw ScsBackendFailure.signingUnavailable("no card session")
      }
      return try outcome.get()
    }

    internal func withCard<Answer: Sendable>(
      timeoutSeconds: Double,
      _ work: @escaping @Sendable (CardOperations) -> Answer?
    ) -> Answer? {
      let semaphore = DispatchSemaphore(value: 0)
      let box = Box<Answer?>(nil)
      let finished = OSAllocatedUnfairLock(initialState: false)
      let task = Task {
        let answer = await CardMaintenance.onReader(work)
        let shouldWrite = finished.withLock { timedOut -> Bool in
          guard !timedOut else { return false }
          timedOut = true
          return true
        }
        if shouldWrite {
          box.value = answer
          semaphore.signal()
        }
      }
      let waitOutcome = semaphore.wait(timeout: .now() + timeoutSeconds)
      if waitOutcome == .timedOut {
        let wonRace = finished.withLock { timedOut -> Bool in
          guard !timedOut else { return false }
          timedOut = true
          return true
        }
        if wonRace {
          task.cancel()
          ScsLog.error("backend: card session timed out")
          return nil
        }
        semaphore.wait()
      }
      return box.value
    }
  }
#endif
