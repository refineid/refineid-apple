// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// The reset form for a card whose PIN 1 and PIN 2 are both blocked:
/// the PUK once, and each new PIN twice.
///
/// Laid out as the activation form: one group for the PUK, then one
/// group per PIN, each headed by its code. Return walks the fields and,
/// on the last one, asks the same question the button asks.
internal struct CredentialResetBothSection: View {
  /// The keyboard path through the section.
  private enum Field: CaseIterable {
    case puk
    case pin1
    case pin1Repeat
    case pin2
    case pin2Repeat

    /// The field's label.
    var name: String {
      switch self {
      case .puk:
        String(localized: "PUK")

      case .pin1:
        CredentialLabels.newPinField(for: .pin1)

      case .pin1Repeat:
        CredentialLabels.repeatPinField(for: .pin1)

      case .pin2:
        CredentialLabels.newPinField(for: .pin2)

      case .pin2Repeat:
        CredentialLabels.repeatPinField(for: .pin2)
      }
    }

    /// Accessibility identifier used for test automation.
    var identifier: String {
      switch self {
      case .puk:
        "managementResetBothPuk"

      case .pin1:
        "managementResetBothPin1"

      case .pin1Repeat:
        "managementResetBothPin1Repeat"

      case .pin2:
        "managementResetBothPin2"

      case .pin2Repeat:
        "managementResetBothPin2Repeat"
      }
    }

    /// The credential the field holds.
    var role: CredentialRole {
      switch self {
      case .puk:
        .puk

      case .pin1, .pin1Repeat:
        .pin1

      case .pin2, .pin2Repeat:
        .pin2
      }
    }
  }

  internal let model: CardManagementModel
  internal let lengths: CardPinLengths

  @State private var puk = ""
  @State private var newPin1 = ""
  @State private var newPin1Repeated = ""
  @State private var newPin2 = ""
  @State private var newPin2Repeated = ""
  @State private var pending: CredentialOperationConfirmation.Operation?
  @FocusState private var focus: Field?

  private var pukIsValid: Bool {
    PinEntryLimits(lengths, role: .puk).accepts(puk)
  }

  private var pin1Entries: CardActivationSection.NewPinEntries {
    CardActivationSection.NewPinEntries(
      new: newPin1, repeated: newPin1Repeated,
      limits: PinEntryLimits(lengths, role: .pin1))
  }

  private var pin2Entries: CardActivationSection.NewPinEntries {
    CardActivationSection.NewPinEntries(
      new: newPin2, repeated: newPin2Repeated,
      limits: PinEntryLimits(lengths, role: .pin2))
  }

  private var isComplete: Bool {
    pukIsValid && pin1Entries.repeatedIsValid && pin2Entries.repeatedIsValid
  }

  internal var body: some View {
    Group {
      Section {
        row(
          .puk,
          text: $puk,
          indicator: CredentialValidationIndicator(valid: pukIsValid, isEmpty: puk.isEmpty))
      } header: {
        Text("PUK")
          .accessibilityAddTraits(.isHeader)
      }
      Section {
        pinRows(for: .pin1)
      } header: {
        Text("Basic PIN 1")
          .accessibilityAddTraits(.isHeader)
      }
      // The button is the last group's footer on the Mac, where a row
      // of its own would draw a box around it.
      Section {
        pinRows(for: .pin2)
      } header: {
        Text("Signature PIN 2")
          .accessibilityAddTraits(.isHeader)
      } footer: {
        #if os(macOS)
          resetButton
        #endif
      }
      #if os(iOS)
        resetButton
      #endif
    }
    .task {
      // See InitialFieldFocus: the window must settle first, or the
      // PUK typed into a freshly opened window goes nowhere.
      #if os(macOS)
        await InitialFieldFocus.settle()
      #endif
      focus = .puk
    }
    .confirmCredentialOperation(
      $pending,
      report: model.report,
      reject: { _ in clearEntries() },
      confirm: { _ in reset() }
    )
  }

  private var resetButton: some View {
    CardFormButton(
      title: "Change",
      identifier: "managementResetBoth",
      enabled: isComplete
        && model.canContactCard
        && model.allowsCredentialOperation(spending: .puk)
        && !model.cardOperationInProgress
    ) {
      focus = nil
      pending = .unblockBoth
    }
  }

  /// One PIN's new value and its repeat.
  @ViewBuilder
  private func pinRows(for role: CredentialRole) -> some View {
    if role == .pin1 {
      row(.pin1, text: $newPin1, indicator: newIndicator(pin1Entries))
      row(.pin1Repeat, text: $newPin1Repeated, indicator: repeatIndicator(pin1Entries))
    } else {
      row(.pin2, text: $newPin2, indicator: newIndicator(pin2Entries))
      row(.pin2Repeat, text: $newPin2Repeated, indicator: repeatIndicator(pin2Entries))
    }
  }

  private func newIndicator(
    _ entries: CardActivationSection.NewPinEntries
  ) -> CredentialValidationIndicator {
    CredentialValidationIndicator(valid: entries.isValid, isEmpty: entries.new.isEmpty)
  }

  private func repeatIndicator(
    _ entries: CardActivationSection.NewPinEntries
  ) -> CredentialValidationIndicator {
    CredentialValidationIndicator(
      valid: entries.repeatedIsValid,
      entriesDiffer: entries.differ,
      isEmpty: entries.repeated.isEmpty)
  }

  /// One secret row, threaded for Return.
  private func row(
    _ field: Field,
    text: Binding<String>,
    indicator: CredentialValidationIndicator
  ) -> some View {
    CredentialSecretField(
      name: field.name,
      text: text,
      revealIdentifier: "\(field.identifier)Reveal",
      field: {
        SecureField(field.name, text: text)
          .textContentType(.oneTimeCode)
          #if os(iOS)
            .keyboardType(.numberPad)
          #endif
          .onValueChange(of: text.wrappedValue) { typed in
            text.wrappedValue = PinEntryLimits(lengths, role: field.role).limited(typed)
          }
          .focused($focus, equals: field)
          .onSubmit { advance(from: field) }
          .accessibilityIdentifier(field.identifier)
      },
      validation: { indicator }
    )
  }

  /// Return advances; on the last field it submits when complete.
  private func advance(from field: Field) {
    let fields = Field.allCases
    guard let place = fields.firstIndex(of: field) else { return }
    let next = fields.index(after: place)
    if next < fields.endIndex {
      focus = fields[next]
    } else if isComplete {
      focus = nil
      pending = .unblockBoth
    }
  }

  /// Runs both resets and destroys every entry before the card answers.
  private func reset() {
    guard isComplete, !model.cardOperationInProgress else { return }
    let pukEntry = puk
    let pin1Entry = newPin1
    let pin2Entry = newPin2
    clearEntries()
    Task {
      _ = await model.unblockBoth(puk: pukEntry, newPin1: pin1Entry, newPin2: pin2Entry)
    }
  }

  /// Destroys every secret entered for this operation.
  private func clearEntries() {
    puk = ""
    newPin1 = ""
    newPin1Repeated = ""
    newPin2 = ""
    newPin2Repeated = ""
    focus = nil
  }
}
