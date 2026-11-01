// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

extension CardManagementView {
  // MARK: Static Functions

  internal static func initialTask(
    for recovery: CredentialRetryHealth.Recovery?
  ) -> ManagementTask {
    switch recovery {
    case .resetPin1, .resetBothPins:
      .resetPin1

    case .resetPin2:
      .resetPin2

    case .useOtherSoftware, .unrecoverable, nil:
      .changePin1
    }
  }

  // MARK: Content Views

  @ViewBuilder
  internal func recoveryGuidanceSection(
    retryHealth: CredentialRetryHealth,
    model: CardManagementModel
  ) -> some View {
    if model.failure == nil, model.notice == nil {
      switch retryHealth.recovery {
      case .resetPin1:
        Section {
          CredentialOutcomeText(
            message: CredentialOutcomeMessage.recoveryGuidance(for: .pin1),
            tone: .notice)
        }

      case .resetPin2:
        Section {
          CredentialOutcomeText(
            message: CredentialOutcomeMessage.recoveryGuidance(for: .pin2),
            tone: .notice)
        }

      case .resetBothPins:
        Section {
          CredentialOutcomeText(
            message: CredentialOutcomeMessage.recoveryGuidance(for: .pin1)
              + "\n"
              + CredentialOutcomeMessage.recoveryGuidance(for: .pin2),
            tone: .notice)
        }

      case .useOtherSoftware:
        Section {
          CredentialOutcomeText(
            message: CredentialOutcomeMessage.otherSoftwareRecovery(),
            tone: .failure)
        }

      case .unrecoverable:
        Section {
          CredentialOutcomeText(
            message: CredentialOutcomeMessage.unrecoverableCard(),
            tone: .failure)
        }

      case nil:
        EmptyView()
      }
    }
  }

  @ViewBuilder
  internal func connectionSection(
    model: CardManagementModel,
    readerCardIsPresent: Bool,
    usesProvidedCardAccessNumber: Bool
  ) -> some View {
    #if os(iOS)
      if !readerCardIsPresent,
        model.transport == .nearField,
        !usesProvidedCardAccessNumber
      {
        Section("NFC") {
          TextField(
            "Card Access Number (CAN)",
            text: Binding(
              get: { model.cardAccessNumber },
              set: { model.cardAccessNumber = $0 }
            )
          )
          .textContentType(.oneTimeCode)
          .keyboardType(.numberPad)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .onValueChange(of: model.cardAccessNumber) { typed in
            model.cardAccessNumber = LimitedDigits.cardAccessNumber(typed)
          }
          .accessibilityIdentifier("managementCardAccessNumber")
          Button("Read card") {
            Task { await model.refresh() }
          }
          .disabled(model.cardOperationInProgress || !model.canContactCard)
          .accessibilityIdentifier("managementReadCard")
        }
      }
    #endif
  }

  /// The both-PINs reset when it is offered, then the task selector and
  /// the chosen task's form.
  @ViewBuilder
  internal func managementForms(
    model: CardManagementModel,
    lengths: CardPinLengths,
    offersBothPinsReset: Bool,
    tasks: [ManagementTask],
    selection: Binding<ManagementTask>
  ) -> some View {
    if offersBothPinsReset, model.notice == nil {
      CredentialResetBothSection(model: model, lengths: lengths)
    }
    if !tasks.isEmpty {
      taskSelector(tasks: tasks, selection: selection)
      if model.notice == nil, tasks.contains(selection.wrappedValue) {
        page(for: selection.wrappedValue, model: model, lengths: lengths)
      }
    }
  }

  /// The form one tab shows.
  @ViewBuilder
  internal func page(
    for task: ManagementTask,
    model: CardManagementModel,
    lengths: CardPinLengths
  ) -> some View {
    switch task {
    case .changePin1:
      CredentialChangeSection(model: model, credential: .pin1, lengths: lengths)

    case .changePin2:
      CredentialChangeSection(model: model, credential: .pin2, lengths: lengths)

    case .resetPin1:
      CredentialUnblockSection(model: model, target: .pin1, lengths: lengths)

    case .resetPin2:
      CredentialUnblockSection(model: model, target: .pin2, lengths: lengths)
    }
  }
}
