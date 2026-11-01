// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import CryptoTokenKit
  import Foundation
  import Observation

  /// Turns CryptoTokenKit's authoritative token events into the status
  /// window's card state without competing for the first card session.
  ///
  /// An activated card publishes its identity token. A recognized new
  /// card publishes an empty activation token. A transport failure
  /// publishes neither and therefore remains processing rather than
  /// being misreported as a permanent card error.
  @MainActor
  @Observable
  internal final class ActivationWatch {
    private enum State {
      case idle
      case reading
      case awaitsActivation
    }

    /// The one watch the status window uses.
    internal static let shared = ActivationWatch()

    /// Seconds a card may stay present without an identity before the
    /// row warns.
    private static let settleSeconds = 10

    /// How long a card may settle before the row warns.
    internal static let settleLimit: Duration = .seconds(settleSeconds)

    private var state = State.idle {
      didSet {
        guard state != oldValue else { return }
        settle.cardWithoutIdentity(state == .reading)
      }
    }

    /// Whether the card in the reader has outlasted ``settleLimit``
    /// without an identity.
    private var settled = false

    @ObservationIgnored private lazy var settle = SettleDeadline(limit: Self.settleLimit) {
      [weak self] expired in
      self?.settled = expired
    }

    @ObservationIgnored private var latestAvailability = LoginIdentityModel.Availability.noCard

    @ObservationIgnored private var paused = false

    @ObservationIgnored private var activationTokenIDs = Set<String>()

    @ObservationIgnored private var tokenWatcher: TKTokenWatcher?

    @ObservationIgnored private var managementRefresh: Task<Void, Never>?

    @ObservationIgnored private var managementRefreshID = 0

    internal let management = CardManagementModel(
      transport: nil,
      activationRequired: false,
      cardAccessNumber: nil,
      activation: nil,
      activationNeeds: nil,
      pinLengths: nil)

    internal var awaitsActivation: Bool {
      state == .awaitsActivation
    }

    internal var isReading: Bool {
      state == .reading
    }

    /// Removal cleanup waits for the same system event that ends the
    /// processing or activation token, not a transient empty-slot pulse.
    internal var defersRemoval: Bool {
      state == .reading || state == .awaitsActivation
    }

    /// Whether a card has stayed present without an identity past the
    /// settle deadline.
    internal var warnsUnavailableCard: Bool { settled }

    internal init() {
      let watcher = TKTokenWatcher()
      tokenWatcher = watcher
      watcher.setInsertionHandler(Self.insertionHandler(for: self))
    }

    /// CryptoTokenKit calls this block on its private XPC queue.
    ///
    /// Build the block outside MainActor isolation, then cross actors
    /// only by scheduling the state mutation explicitly.
    nonisolated private static func insertionHandler(
      for watch: ActivationWatch
    ) -> @Sendable (String) -> Void {
      { [weak watch] tokenID in
        Task { @MainActor [weak watch] in
          watch?.tokenInserted(tokenID)
        }
      }
    }

    /// Removal callbacks have the same CryptoTokenKit queue contract as
    /// insertion callbacks and must use the same isolation boundary.
    nonisolated private static func removalHandler(
      for watch: ActivationWatch
    ) -> @Sendable (String) -> Void {
      { [weak watch] tokenID in
        Task { @MainActor [weak watch] in
          watch?.tokenRemoved(tokenID)
        }
      }
    }

    internal func observe(
      availability: LoginIdentityModel.Availability,
      paused: Bool,
      identity _: LoginIdentityModel
    ) {
      latestAvailability = availability
      self.paused = paused

      #if DEBUG
        if DebugActivationPreview.isEnabled() {
          state = .awaitsActivation
          return
        }
      #endif

      reconcile()
    }

    private func tokenInserted(_ tokenID: String) {
      guard ActivationTokenIdentity.recognizes(tokenID: tokenID) else { return }
      activationTokenIDs.insert(tokenID)
      tokenWatcher?.addRemovalHandler(
        Self.removalHandler(for: self),
        forTokenID: tokenID
      )
      reconcile()
    }

    private func tokenRemoved(_ tokenID: String) {
      activationTokenIDs.remove(tokenID)
      reconcile()
    }

    /// The complete transition table.
    ///
    /// Token presence outranks raw slot absence because CCID protocol
    /// resets can emit the latter while the logical token remains
    /// present.
    private func reconcile() {
      guard !paused else {
        stopManagementRefresh()
        state = .idle
        return
      }

      if DemoMode.shared.isActive {
        if DemoMode.shared.state.card.cardPresent, DemoMode.shared.activationNeeds.any {
          state = .awaitsActivation
          startManagementRefreshIfNeeded()
        } else {
          stopManagementRefresh()
          state = .idle
        }
        return
      }

      if !activationTokenIDs.isEmpty {
        state = .awaitsActivation
        startManagementRefreshIfNeeded()
      } else if latestAvailability == .ready {
        stopManagementRefresh()
        state = .idle
      } else if latestAvailability == .cardWithoutIdentity {
        stopManagementRefresh()
        state = .reading
      } else {
        stopManagementRefresh()
        state = .idle
      }
    }

    /// The activation token is inserted only after the extension has
    /// finished its read, so this read no longer races token creation.
    ///
    /// It merely populates the activation form and never changes a PIN.
    private func startManagementRefreshIfNeeded() {
      guard managementRefresh == nil else { return }
      managementRefreshID += 1
      let refreshGeneration = managementRefreshID
      managementRefresh = Task { @MainActor [weak self] in
        guard let self else { return }
        await management.refresh()
        guard managementRefreshID == refreshGeneration, !Task.isCancelled else { return }
        managementRefresh = nil
      }
    }

    private func stopManagementRefresh() {
      managementRefreshID += 1
      managementRefresh?.cancel()
      managementRefresh = nil
    }

    internal func stop() {
      stopManagementRefresh()
      state = .idle
    }
  }

#endif
