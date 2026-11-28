// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Combine
  import Foundation
  import Observation

  /// Live Combine and Observation wiring for ``CardIssueAttention``.
  extension CardIssueAttention {
    nonisolated private static func observationChangeHandler(
      for attention: CardIssueAttention
    ) -> @Sendable () -> Void {
      { [weak attention] in
        Task { @MainActor [weak attention] in
          guard let attention, attention.started else { return }
          attention.evaluateCurrentState()
          attention.observeObservableSources()
        }
      }
    }

    internal func subscribeToPublishedSources() {
      let presence = CardPresence.shared
      let health = CredentialRetryHealth.shared
      let demo = DemoMode.shared

      presence.$isReaderCardPresent
        .removeDuplicates()
        .sink { [weak self] present in
          guard let self, started else { return }
          if !present {
            handleCardAbsent(
              hasCompletedInitialScan: presence.hasCompletedInitialScan,
              defersRemoval: ActivationWatch.shared.defersRemoval
            )
          } else {
            scheduleEvaluation()
          }
        }
        .store(in: &cancellables)

      presence.$readerCardInsertionGeneration
        .removeDuplicates()
        .sink { [weak self] _ in self?.scheduleEvaluation() }
        .store(in: &cancellables)

      presence.$hasCompletedInitialScan
        .removeDuplicates()
        .sink { [weak self] _ in self?.scheduleEvaluation() }
        .store(in: &cancellables)

      health.$report
        .removeDuplicates()
        .sink { [weak self] _ in self?.scheduleEvaluation() }
        .store(in: &cancellables)

      health.$level
        .removeDuplicates()
        .sink { [weak self] _ in self?.scheduleEvaluation() }
        .store(in: &cancellables)

      health.$pin2RequiresChangeBeforeSigning
        .removeDuplicates()
        .sink { [weak self] _ in self?.scheduleEvaluation() }
        .store(in: &cancellables)

      health.$isEstonianCard
        .removeDuplicates()
        .sink { [weak self] _ in self?.scheduleEvaluation() }
        .store(in: &cancellables)

      demo.$isActive
        .removeDuplicates()
        .sink { [weak self] _ in self?.scheduleEvaluation() }
        .store(in: &cancellables)
    }

    internal func observeObservableSources() {
      guard started else { return }
      let onChange = Self.observationChangeHandler(for: self)
      withObservationTracking {
        _ = LoginIdentityModel.shared.isReady
        _ = ActivationWatch.shared.awaitsActivation
        _ = ActivationWatch.shared.defersRemoval
        _ = SafariWebEidExtensionStatus.shared.state
      } onChange: {
        onChange()
      }
    }

    internal func scheduleEvaluation() {
      Task { @MainActor [weak self] in
        guard let self, started else { return }
        evaluateCurrentState()
      }
    }

    internal func evaluateCurrentState() {
      let presence = CardPresence.shared
      let identity = LoginIdentityModel.shared
      let activation = ActivationWatch.shared
      let health = CredentialRetryHealth.shared
      let safari = SafariWebEidExtensionStatus.shared

      let snapshot = Snapshot(
        isDemoMode: DemoMode.shared.isActive,
        hasActiveWebEidRequest: WebEidCoordinator.shared.hasActiveRequest,
        hasCompletedInitialScan: presence.hasCompletedInitialScan,
        cardInsertionID: presence.readerCardInsertionGeneration,
        isReaderCardPresent: presence.isReaderCardPresent,
        defersRemoval: activation.defersRemoval,
        isTokenReady: identity.isReady,
        awaitsActivation: activation.awaitsActivation,
        hasRetryReport: health.report != nil,
        retryHealthLevel: health.level,
        pin2RequiresChangeBeforeSigning: health.pin2RequiresChangeBeforeSigning,
        isEstonianCard: health.isEstonianCard,
        safariExtensionState: safari.state
      )
      evaluate(snapshot)
    }
  }

#endif
