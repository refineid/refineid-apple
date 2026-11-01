// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// The activation form: the activation PIN from the issuance
/// letter and the two new PINs.
///
/// The driver classifies the card and refuses a wrong-length code
/// before anything is spent.
internal struct CardActivationSection: View {
  internal let model: CardManagementModel
  internal let onActivated: () -> Void

  @State private var entry = ""
  @State private var newPin1 = ""
  @State private var newPin1Repeated = ""
  @State private var newPin2 = ""
  @State private var newPin2Repeated = ""
  @State private var pending: CredentialOperationConfirmation.Operation?
  @FocusState private var focus: Field?

  private var activationEntryIsValid: Bool {
    guard let scheme = model.activationScheme else { return false }
    return entry.count == scheme.activationEntryDigitCount
  }

  private var pin1Entries: NewPinEntries {
    NewPinEntries(
      new: newPin1, repeated: newPin1Repeated,
      bounds: Pin1.minimumDigitCount...Pin1.maximumDigitCount)
  }

  private var pin2Entries: NewPinEntries {
    NewPinEntries(
      new: newPin2, repeated: newPin2Repeated,
      bounds: Pin2.minimumDigitCount...Pin2.maximumDigitCount)
  }

  /// Ready only when the activation PIN has the exact length the card's
  /// scheme takes and every requested new PIN is valid and repeated.
  private var isComplete: Bool {
    activationEntryIsValid
      && (!asksPin1 || pin1Entries.isValid && pin1Entries.repeatedIsValid)
      && (!asksPin2 || pin2Entries.isValid && pin2Entries.repeatedIsValid)
  }

  internal var body: some View {
    Group {
      Section("Card activation") {
        activationEntryRow
      }
      if asksPin1 {
        Section {
          pin1Rows
        }
      }
      if asksPin2 {
        Section {
          pin2Rows
        }
      }
      activationButton
    }
    .task {
      // This form never placed focus at all, so its first field had
      // to be found with a pointer. See InitialFieldFocus for why the
      // window is allowed to settle first.
      #if os(macOS)
        await InitialFieldFocus.settle()
      #endif
      focus = .entry
    }
    .confirmCredentialOperation(
      $pending,
      report: model.report,
      reject: { _ in clearEntries() },
      confirm: { _ in activate() }
    )
  }

  private var activationButton: some View {
    Button {
      focus = nil
      pending = .activate
    } label: {
      Text("Activate Card")
        #if os(iOS)
          .frame(maxWidth: .infinity)
        #endif
    }
    .buttonStyle(.borderedProminent)
    #if os(iOS)
      .controlSize(.large)
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)
    #else
      .frame(maxWidth: .infinity)
      .listRowBackground(Color.clear)
    #endif
    .keyboardShortcut(.defaultAction)
    .disabled(
      !isComplete
        || !model.canContactCard
        || !model.allowsActivationOperation
        || model.cardOperationInProgress
    )
    .accessibilityIdentifier("managementActivate")
  }

  /// The activation code: its own group, above one group per PIN.
  private var activationEntryRow: some View {
    CredentialSecretField(
      name: String(localized: "Activation PIN"),
      text: $entry,
      revealIdentifier: "managementActivationEntryReveal",
      field: {
        SecureField("Activation PIN", text: $entry)
          .textContentType(.oneTimeCode)
          #if os(iOS)
            .keyboardType(.numberPad)
          #endif
          .onValueChange(of: entry) { typed in
            entry = LimitedDigits.puk(typed)
          }
          .focused($focus, equals: .entry)
          .onSubmit { advance(from: .entry) }
          .accessibilityIdentifier("managementActivationEntry")
      },
      validation: {
        CredentialValidationIndicator(
          valid: activationEntryIsValid,
          isEmpty: entry.isEmpty)
      }
    )
  }

  /// PIN 1's new value and its repeat, shown only while the card still
  /// waits for it: an interrupted activation left one PIN set, and
  /// asking for a value the card will not take invites a retry spent
  /// on nothing.
  @ViewBuilder private var pin1Rows: some View {
    CredentialSecretField(
      name: CredentialLabels.newPinField(for: .pin1),
      text: $newPin1,
      revealIdentifier: "managementActivationPin1Reveal",
      field: {
        SecureField(CredentialLabels.newPinField(for: .pin1), text: $newPin1)
          .textContentType(.oneTimeCode)
          #if os(iOS)
            .keyboardType(.numberPad)
          #endif
          .onValueChange(of: newPin1) { typed in
            newPin1 = LimitedDigits.pin1(typed)
          }
          .focused($focus, equals: .pin1)
          .onSubmit { advance(from: .pin1) }
          .accessibilityIdentifier("managementActivationPin1")
      },
      validation: {
        CredentialValidationIndicator(
          valid: pin1Entries.isValid,
          isEmpty: newPin1.isEmpty)
      }
    )
    CredentialSecretField(
      name: CredentialLabels.repeatPinField(for: .pin1),
      text: $newPin1Repeated,
      revealIdentifier: "managementActivationPin1RepeatReveal",
      field: {
        SecureField(CredentialLabels.repeatPinField(for: .pin1), text: $newPin1Repeated)
          .textContentType(.oneTimeCode)
          #if os(iOS)
            .keyboardType(.numberPad)
          #endif
          .onValueChange(of: newPin1Repeated) { typed in
            newPin1Repeated = LimitedDigits.pin1(typed)
          }
          .focused($focus, equals: .pin1Repeat)
          .onSubmit { advance(from: .pin1Repeat) }
          .accessibilityIdentifier("managementActivationPin1Repeat")
      },
      validation: {
        CredentialValidationIndicator(
          valid: pin1Entries.repeatedIsValid,
          entriesDiffer: pin1Entries.differ,
          isEmpty: newPin1Repeated.isEmpty)
      }
    )
  }

  /// PIN 2's new value and its repeat, under the same rule as PIN 1.
  @ViewBuilder private var pin2Rows: some View {
    CredentialSecretField(
      name: CredentialLabels.newPinField(for: .pin2),
      text: $newPin2,
      revealIdentifier: "managementActivationPin2Reveal",
      field: {
        SecureField(CredentialLabels.newPinField(for: .pin2), text: $newPin2)
          .textContentType(.oneTimeCode)
          #if os(iOS)
            .keyboardType(.numberPad)
          #endif
          .onValueChange(of: newPin2) { typed in
            newPin2 = LimitedDigits.pin2(typed)
          }
          .focused($focus, equals: .pin2)
          .onSubmit { advance(from: .pin2) }
          .accessibilityIdentifier("managementActivationPin2")
      },
      validation: {
        CredentialValidationIndicator(
          valid: pin2Entries.isValid,
          isEmpty: newPin2.isEmpty)
      }
    )
    CredentialSecretField(
      name: CredentialLabels.repeatPinField(for: .pin2),
      text: $newPin2Repeated,
      revealIdentifier: "managementActivationPin2RepeatReveal",
      field: {
        SecureField(CredentialLabels.repeatPinField(for: .pin2), text: $newPin2Repeated)
          .textContentType(.oneTimeCode)
          #if os(iOS)
            .keyboardType(.numberPad)
          #endif
          .onValueChange(of: newPin2Repeated) { typed in
            newPin2Repeated = LimitedDigits.pin2(typed)
          }
          .focused($focus, equals: .pin2Repeat)
          .onSubmit { advance(from: .pin2Repeat) }
          .accessibilityIdentifier("managementActivationPin2Repeat")
      },
      validation: {
        CredentialValidationIndicator(
          valid: pin2Entries.repeatedIsValid,
          entriesDiffer: pin2Entries.differ,
          isEmpty: newPin2Repeated.isEmpty)
      }
    )
  }

  /// Return advances through the fields that are shown; on the last
  /// one it asks the same question the button asks.
  private func advance(from field: Field) {
    guard let place = shownFields.firstIndex(of: field) else { return }
    let next = shownFields.index(after: place)
    if next < shownFields.endIndex {
      focus = shownFields[next]
    } else if isComplete {
      focus = nil
      pending = .activate
    }
  }

  /// Runs activation and destroys every entry after the card responds.
  private func activate() {
    guard isComplete, !model.cardOperationInProgress else { return }
    let activationEntry = entry
    let pin1Entry = asksPin1 ? newPin1 : nil
    let pin2Entry = asksPin2 ? newPin2 : nil
    clearEntries()
    Task {
      let accepted = await model.activate(
        entry: activationEntry,
        newPin1: pin1Entry,
        newPin2: pin2Entry
      )
      if accepted {
        onActivated()
      }
    }
  }

  /// Destroys the activation entry and every new PIN held by the form.
  private func clearEntries() {
    entry = ""
    newPin1 = ""
    newPin1Repeated = ""
    newPin2 = ""
    newPin2Repeated = ""
    focus = nil
  }
}
