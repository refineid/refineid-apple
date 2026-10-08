// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// The card-management window: attempts remaining at a glance, and
/// one management task at a time.
///
/// The window reads the card's state and leads with what the card
/// needs: a blocked PIN opens on Unblock, a healthy card on a PIN
/// change; activation is there when asked for, not permanently on
/// screen. Every operation probes the relevant retry counter first
/// and refuses below the floor - the card's counters are the real
/// access control, and this window never spends a near-last attempt.
/// Entries are never stored and never echoed anywhere.
internal struct CardManagementView: View {
  // MARK: Nested Types

  private struct ReaderReadKey: Equatable {
    let isPresent: Bool
    let isReady: Bool
    let transport: CardMaintenance.Transport
  }

  // MARK: Static Properties

  #if os(macOS)
    /// Internal, not private: the counter presentation lives in
    /// CardManagementView+Attempts.swift and lays out the same row.
    internal static let rowSymbolSpacing: CGFloat = 4

    private static let attemptsSpacing: CGFloat = 14

    private static let barHorizontalPadding: CGFloat = 16

    private static let barVerticalPadding: CGFloat = 6

    private static let barLineSpacing: CGFloat = 4

    /// The window's own width, which grows with the text inside it.
    @ScaledMetric(relativeTo: .body)
    private var windowWidth: CGFloat = 560
  #endif

  // MARK: SwiftUI Properties

  @ObservedObject private var cardPresence = CardPresence.shared
  @ObservedObject private var retryHealth = CredentialRetryHealth.shared
  @Environment(\.dismiss)
  private var dismiss
  @StateObject private var model: CardManagementModel
  @State private var task: ManagementTask
  @State private var hasChosenTask = false

  // MARK: Properties

  private let startsWithReaderCard: Bool
  private let usesProvidedCardAccessNumber: Bool
  private let activationRequired: Bool
  private let onActivationSucceeded: (() -> Void)?

  // MARK: Computed Properties

  private var readerCardIsPresent: Bool {
    if DemoMode.shared.isActive {
      return DemoMode.shared.isReaderCardPresent
    }
    return cardPresence.hasCompletedInitialScan
      ? cardPresence.isReaderCardPresent
      : startsWithReaderCard
  }

  private var readerCardIsReady: Bool {
    if DemoMode.shared.isActive {
      return DemoMode.shared.isReaderCardPresent
    }
    return cardPresence.hasCompletedInitialScan && cardPresence.isReaderCardReady
  }

  private var readerReadKey: ReaderReadKey {
    ReaderReadKey(
      isPresent: readerCardIsPresent,
      isReady: readerCardIsReady,
      transport: model.transport
    )
  }

  /// The tasks this card can actually be asked to do.
  ///
  /// Activation is offered only while the card is still in its
  /// factory state; for a card in use there is no such operation,
  /// and showing it would invite a retry spent for nothing.
  /// Whether this card is still waiting to be taken into use.
  ///
  /// Activation sets both PINs from the code in the issuance letter,
  /// so while it is available there is nothing else to offer: a PIN
  /// that has never been set cannot be changed, and resetting one
  /// would be a second door to the same operation with a retry spent
  /// on getting there.
  private var awaitsActivation: Bool {
    activationRequired || model.offersActivation
  }

  /// A critical card is a recovery workflow, never a PIN-change workflow.
  private var availableTasks: [ManagementTask] {
    #if os(macOS)
      guard readerCardIsPresent else { return [] }
    #endif
    return switch retryHealth.recovery {
    case .resetPin1, .resetPin2:
      [.resetPin1, .resetPin2]

    case .useOtherSoftware, .unrecoverable:
      []

    case nil:
      ManagementTask.allCases
    }
  }

  // MARK: Content Properties

  internal var body: some View {
    taskSection
      #if os(macOS)
        .frame(minWidth: windowWidth)
      #else
        .navigationTitle(
          awaitsActivation ? "RefineID" : "Personal Identification Numbers"
        )
        .navigationBarTitleDisplayMode(awaitsActivation ? .large : .inline)
      #endif
      #if os(macOS)
        .safeAreaInset(edge: .bottom, spacing: 0) {
          if !awaitsActivation, model.report != nil {
            attemptsBar(model: model)
          }
        }
      #endif
      #if os(macOS)
        .task(id: readerCardIsPresent) {
          if readerCardIsPresent {
            await model.refresh()
          } else {
            model.cardRemoved()
            await model.refresh()
          }
        }
      #endif
      #if os(iOS)
        .task(id: readerReadKey) {
          if readerCardIsPresent {
            model.transport = .reader
            guard readerCardIsReady else { return }
            // The token insertion event has already classified this as
            // an unactivated card. Do not hold the activation form behind
            // a second full credential probe; activation performs its own
            // retry-floor checks inside the exclusive card session.
            if awaitsActivation {
              #if FEATURE_CARD_ACTIVATION
                await model.detectActivationScheme()
              #endif
              // Gated, the destination is a refusal that asks the card
              // for nothing, so nothing is probed either.
            } else {
              await model.refresh()
            }
          } else if model.transport == .reader {
            model.cardRemoved()
            dismiss()
          }
        }
      #endif
      .onValueChange(of: model.report) { report in
        suggestTask(from: report)
      }
      #if os(macOS)
        .announcesOutcome(model.failure)
        .announcesOutcome(model.notice)
      #endif
  }

  /// One tab per task, and only the chosen one on screen.
  ///
  /// Nested TabView items are hoisted into the Settings window's own
  /// tab bar, so the four tasks stay a segmented control inside this
  /// pane. The labels are short: the action and the PIN, once.
  @ViewBuilder private var taskSection: some View {
    if awaitsActivation {
      #if FEATURE_CARD_ACTIVATION
        Form {
          connectionSection(
            model: model,
            readerCardIsPresent: readerCardIsPresent,
            usesProvidedCardAccessNumber: usesProvidedCardAccessNumber
          )
          CardActivationSection(
            model: model,
            onActivated: activationCompleted)
          CardOutcomeSection(model: model)
        }
        .formStyle(.grouped)
      #else
        // The destination still exists; the build's answer differs. No
        // connection section either: a form that cannot act on the card
        // has no business inviting one.
        Form {
          CardActivationUnavailableSection()
        }
        .formStyle(.grouped)
      #endif
    } else {
      Form {
        // The card's problem is the first thing on the page; the
        // forms to solve it follow.
        recoveryGuidanceSection(retryHealth: retryHealth, model: model)
        connectionSection(
          model: model,
          readerCardIsPresent: readerCardIsPresent,
          usesProvidedCardAccessNumber: usesProvidedCardAccessNumber
        )
        let tasks = availableTasks
        if !tasks.isEmpty {
          taskSelector(tasks: tasks, selection: $task)
          if model.notice == nil, tasks.contains(task) {
            page(for: task, model: model)
          }
        }
        CardOutcomeSection(model: model)
      }
      .formStyle(.grouped)
      .disabled(model.working)
      .onValueChange(of: task) { _ in
        hasChosenTask = true
        model.clearOutcome()
      }
    }
  }

  // MARK: Lifecycle

  internal init(
    readerCardIsPresent: Bool,
    activationRequired: Bool,
    cardAccessNumber: String?,
    activationScheme: ActivationScheme?,
    activationNeeds: CardActivationNeeds?,
    onActivationSucceeded: (() -> Void)?
  ) {
    startsWithReaderCard = readerCardIsPresent
    self.activationRequired = activationRequired
    let providesCardAccessNumber =
      cardAccessNumber?.count == CardAccessNumber.digitCount
    usesProvidedCardAccessNumber = providesCardAccessNumber
    self.onActivationSucceeded = onActivationSucceeded
    // Built before the wrapper, because a state object takes its value as
    // an escaping autoclosure, which cannot read a half-initialised view.
    let initialModel = CardManagementModel(
      transport: readerCardIsPresent
        ? .reader
        : (providesCardAccessNumber ? .nearField : nil),
      activationRequired: activationRequired,
      cardAccessNumber: cardAccessNumber,
      activationScheme: activationScheme,
      activationNeeds: activationNeeds
    )
    _model = StateObject(wrappedValue: initialModel)
    _task = State(
      initialValue: Self.initialTask(
        for: CredentialRetryHealth.shared.recovery)
    )
  }

  /// Management with no activation outcome to report.
  internal init(
    readerCardIsPresent: Bool,
    activationRequired: Bool,
    cardAccessNumber: String?
  ) {
    self.init(
      readerCardIsPresent: readerCardIsPresent,
      activationRequired: activationRequired,
      cardAccessNumber: cardAccessNumber,
      activationScheme: nil,
      activationNeeds: nil,
      onActivationSucceeded: nil
    )
  }

  // MARK: Functions

  private func activationCompleted() {
    onActivationSucceeded?()
    dismiss()
  }

  /// Opens on what the card needs, until the holder chooses.
  private func suggestTask(from report: CredentialProbeReport?) {
    guard !awaitsActivation, let report else { return }
    let recoveryTask: ManagementTask? =
      switch retryHealth.recovery {
      case .resetPin1:
        .resetPin1

      case .resetPin2:
        .resetPin2

      case .useOtherSoftware, .unrecoverable, nil:
        nil
      }
    if let recoveryTask {
      if !availableTasks.contains(task)
        || (!hasChosenTask && model.notice == nil)
      {
        task = recoveryTask
      }
      return
    }
    guard !hasChosenTask else { return }
    let blocked: [RetryProbeOutcome] = [.locked, .invalidated]
    // Land on the credential that is actually blocked, so the form in
    // front of the holder spends the one they came for. PIN 1 first
    // when both are: it is the one a card needs to be usable at all.
    if blocked.contains(report.pin1) {
      task = .resetPin1
    } else if blocked.contains(report.pin2) {
      task = .resetPin2
    }
  }
}
