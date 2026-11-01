// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// The reset form: the PUK, and the new value twice.
///
/// The card resets the retry counter and takes the new value whether
/// or not the credential was blocked.
///
/// A wrong PUK spends the PUK itself and exhausting it is terminal
/// for the card, which is why the driver holds the retry floor
/// against the PUK's counter before anything is sent. Keyboard-first:
/// Return advances from field to field, and on the last field it
/// submits when the entries are complete.
internal struct CredentialUnblockSection: View {
  /// The keyboard path through the section.
  private enum Field {
    case puk
    case new
    case repeated
  }

  internal let model: CardManagementModel

  /// The credential this form unblocks, chosen before the form is
  /// shown rather than inside it.
  internal let target: CredentialRole

  /// The on-screen name of that credential, so the button and the
  /// fields say which one they mean.
  private var targetName: String {
    target == .pin2 ? "PIN 2" : "PIN 1"
  }

  /// The same name without its space, for accessibility identifiers
  /// that tests match exactly.
  private var identifierName: String {
    targetName.replacingOccurrences(of: " ", with: "")
  }

  @State private var puk = ""
  @State private var new = ""
  @State private var repeated = ""
  @State private var pending: CredentialOperationConfirmation.Operation?
  @FocusState private var focus: Field?

  /// The entry bounds of the targeted PIN.
  private var targetBounds: ClosedRange<Int> {
    target == .pin2
      ? Pin2.minimumDigitCount...Pin2.maximumDigitCount
      : Pin1.minimumDigitCount...Pin1.maximumDigitCount
  }

  /// Ready when the PUK and both new entries can possibly be right.
  private var pukIsValid: Bool {
    (Puk.minimumDigitCount...Puk.maximumDigitCount).contains(puk.count)
  }

  private var newIsValid: Bool {
    targetBounds.contains(new.count)
  }

  private var repeatedIsValid: Bool {
    newIsValid && repeated == new
  }

  private var entriesDiffer: Bool {
    newIsValid && targetBounds.contains(repeated.count) && repeated != new
  }

  private var isComplete: Bool {
    pukIsValid && newIsValid && repeatedIsValid
  }

  internal var body: some View {
    Group {
      // The button is the group's footer on the Mac, where a row of its
      // own would draw a box around it.
      #if os(macOS)
        Section {
          entryRows
        } footer: {
          resetButton
        }
      #else
        Section {
          entryRows
        }
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
      confirm: { _ in unblock() }
    )
  }

  /// The action named with the credential's everyday term.
  private var resetTitle: LocalizedStringKey {
    target == .pin2 ? "Reset Signature PIN 2" : "Reset Basic PIN 1"
  }

  private var resetButton: some View {
    Button {
      focus = nil
      pending = .unblock(target)
    } label: {
      Text(resetTitle)
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
        || !model.allowsCredentialOperation(spending: .puk)
        || model.cardOperationInProgress
    )
    .accessibilityIdentifier("managementReset\(identifierName)")
  }

  /// The target picker and the three secret fields, threaded for
  /// Return.
  @ViewBuilder private var entryRows: some View {
    CredentialSecretField(
      name: String(localized: "PUK"),
      text: $puk,
      revealIdentifier: "managementReset\(identifierName)PukReveal",
      field: {
        SecureField("PUK", text: $puk)
          .textContentType(.oneTimeCode)
          #if os(iOS)
            .keyboardType(.numberPad)
          #endif
          .onValueChange(of: puk) { typed in
            puk = LimitedDigits.puk(typed)
          }
          .focused($focus, equals: .puk)
          .onSubmit { advance(from: .puk) }
          .accessibilityIdentifier("managementReset\(identifierName)Puk")
      },
      validation: {
        CredentialValidationIndicator(
          valid: pukIsValid,
          isEmpty: puk.isEmpty)
      }
    )
    CredentialSecretField(
      name: CredentialLabels.newPinField(for: target),
      text: $new,
      revealIdentifier: "managementReset\(identifierName)NewReveal",
      field: {
        SecureField(CredentialLabels.newPinField(for: target), text: $new)
          .textContentType(.oneTimeCode)
          #if os(iOS)
            .keyboardType(.numberPad)
          #endif
          .onValueChange(of: new) { typed in
            new = LimitedDigits.pin(typed)
          }
          .focused($focus, equals: .new)
          .onSubmit { advance(from: .new) }
          .accessibilityIdentifier("managementReset\(identifierName)New")
      },
      validation: {
        CredentialValidationIndicator(
          valid: newIsValid,
          isEmpty: new.isEmpty)
      }
    )
    CredentialSecretField(
      name: CredentialLabels.repeatPinField(for: target),
      text: $repeated,
      revealIdentifier: "managementReset\(identifierName)RepeatReveal",
      field: {
        SecureField(CredentialLabels.repeatPinField(for: target), text: $repeated)
          .textContentType(.oneTimeCode)
          #if os(iOS)
            .keyboardType(.numberPad)
          #endif
          .onValueChange(of: repeated) { typed in
            repeated = LimitedDigits.pin(typed)
          }
          .focused($focus, equals: .repeated)
          .onSubmit { advance(from: .repeated) }
          .accessibilityIdentifier("managementReset\(identifierName)Repeat")
      },
      validation: {
        CredentialValidationIndicator(
          valid: repeatedIsValid,
          entriesDiffer: entriesDiffer,
          isEmpty: repeated.isEmpty)
      }
    )
  }

  /// Return advances; on the last field it submits when complete.
  private func advance(from field: Field) {
    switch field {
    case .puk:
      focus = .new

    case .new:
      focus = .repeated

    case .repeated:
      // Return on the last field asks the same question the button
      // asks; the PUK is the one counter that cannot be restored.
      if isComplete {
        focus = nil
        pending = .unblock(target)
      }
    }
  }

  /// Runs the unblock and destroys every entry after the card responds.
  private func unblock() {
    guard isComplete, !model.cardOperationInProgress else { return }
    let unblockTarget = target
    let pukEntry = puk
    let newEntry = new
    clearEntries()
    Task {
      _ = await model.unblock(target: unblockTarget, puk: pukEntry, new: newEntry)
    }
  }

  /// Destroys every secret entered for this operation.
  private func clearEntries() {
    puk = ""
    new = ""
    repeated = ""
    focus = nil
  }
}
