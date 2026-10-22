// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(MultipeerConnectivity) && canImport(RappEngine)
  import Foundation
  import RappEngine

  /// Timing policy for one requester-side RAPP operation: the lifetime the
  /// operation is granted, the bound on the synchronous wait, and the
  /// window for finding the custodian at all.
  ///
  /// Session liveness is the protocol's own (RAPP v26.10.21 §8.3).
  public struct RappRequesterPolicy: Sendable, Equatable {
    private enum Timing {
      static let interactiveOperationLifetimeMilliseconds: UInt64 = 120_000
      static let synchronousWaitTimeoutSeconds: TimeInterval = 125
    }

    /// Longest wait for a paired device to be found at all.
    ///
    /// Long enough for a phone that is there, short enough that a phone
    /// that is not does not hold the screen.
    public static let defaultDiscoveryTimeout: TimeInterval = 12

    /// Provisional interactive policy.
    ///
    /// It is injectable so measured transport behavior can revise policy
    /// without adding UI timing heuristics.
    public static let interactive = Self(
      maximumOperationLifetimeMilliseconds: Timing.interactiveOperationLifetimeMilliseconds,
      synchronousWaitTimeout: Timing.synchronousWaitTimeoutSeconds
    )

    // MARK: Properties

    /// Operation lifetime granted to the RAPP runtime and sent as the
    /// expiry when the operation begins.
    public let maximumOperationLifetimeMilliseconds: UInt64
    /// Longest time ``RappPersistentRequesterClient/perform(_:)`` blocks
    /// before failing as timed out.
    public let synchronousWaitTimeout: TimeInterval

    /// Longest wait for a paired device to be found at all.
    public let discoveryTimeout: TimeInterval

    /// Composes a policy from explicit timing values.
    public init(
      maximumOperationLifetimeMilliseconds: UInt64,
      synchronousWaitTimeout: TimeInterval,
      discoveryTimeout: TimeInterval = Self.defaultDiscoveryTimeout
    ) {
      self.maximumOperationLifetimeMilliseconds = maximumOperationLifetimeMilliseconds
      self.synchronousWaitTimeout = synchronousWaitTimeout
      self.discoveryTimeout = discoveryTimeout
    }
  }
#endif
