// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// One PIN's change form: the current value, the new one twice, and
/// a Change that stays disabled until the entries can possibly be
/// right.
///
/// Keyboard-first: Return advances from field to field, and on the
/// last field it submits when the entries are complete.
internal struct CredentialChangeSection: View {
  /// Which PIN this section changes; only the two PINs change here.
  internal enum Credential {
    case pin1
    case pin2

    /// The on-screen name.
    ///
    /// Written the way the holder's own card documentation writes
    /// it, with the space, and used wherever a field or a button
    /// names the credential it spends.
    internal var name: String {
      switch self {
      case .pin1:
        "PIN 1"

      case .pin2:
        "PIN 2"
      }
    }

    /// The name used in accessibility identifiers, which tests match
    /// exactly and which therefore carries no space.
    internal var identifierName: String {
      name.replacingOccurrences(of: " ", with: "")
    }

    /// The full everyday name, written to sit inside a longer label.
    internal var everydayName: String {
      switch self {
      case .pin1:
        String(localized: "basic PIN")

      case .pin2:
        String(localized: "signature PIN")
      }
    }

    /// The entry bounds of this PIN.
    internal var digitBounds: ClosedRange<Int> {
      switch self {
      case .pin1:
        Pin1.minimumDigitCount...Pin1.maximumDigitCount

      case .pin2:
        Pin2.minimumDigitCount...Pin2.maximumDigitCount
      }
    }
  }

  /// The keyboard path through the section.
  private enum Field {
    case current
    case new
    case repeated
  }

  internal let model: CardManagementModel
  internal let credential: Credential

  @State private var current = ""
  @State private var new = ""
  @State private var repeated = ""
  @State private var pending: CredentialOperationConfirmation.Operation?
  @FocusState private var focus: Field?

  /// The role this section changes, as the card names it.
  private var role: CredentialRole {
    switch credential {
    case .pin1:
      .pin1

    case .pin2:
      .pin2
    }
  }

  /// Ready when every entry is inside its bounds and the new value
  /// is typed identically twice.
  private var currentIsValid: Bool {
    credential.digitBounds.contains(current.count)
  }

  private var newIsValid: Bool {
    credential.digitBounds.contains(new.count)
  }

  private var repeatedIsValid: Bool {
    newIsValid && repeated == new
  }

  private var entriesDiffer: Bool {
    newIsValid
      && credential.digitBounds.contains(repeated.count)
      && repeated != new
  }

  /// A card write that replaces a PIN with the same value has no useful
  /// effect.
  ///
  /// Flag every completed row so the holder can see that the form as a
  /// whole, rather than one particular entry, needs to change.
  private var newPinMatchesCurrent: Bool {
    currentIsValid && repeatedIsValid && current == new
  }

  private var isComplete: Bool {
    currentIsValid && newIsValid && repeatedIsValid && !newPinMatchesCurrent
  }

  internal var body: some View {
    Group {
      // The button is the group's footer on the Mac, where a row of its
      // own would draw a box around it.
      #if os(macOS)
        Section {
          entryRows
        } footer: {
          changeButton
        }
      #else
        Section {
          entryRows
        }
        changeButton
      #endif
    }
    // Focus is placed after the window has settled, not as the form
    // appears. Measured: assigning it in `onAppear`, and declaring it
    // with `defaultFocus`, both left every field empty -- typing a
    // PIN a second and a half after the window opened put the digits
    // nowhere, so a keyboard user had to find the first field with a
    // pointer before the keyboard did anything at all.
    .task {
      // A yield past the window becoming key: assigning focus as the
      // form appears, and declaring it with `defaultFocus`, were both
      // measured leaving every field empty, so a PIN typed a second
      // after the window opened went nowhere and the keyboard could
      // not start the operation at all.
      #if os(macOS)
        await InitialFieldFocus.settle()
      #endif
      focus = .current
    }
    .confirmCredentialOperation(
      $pending,
      report: model.report,
      reject: { _ in clearEntries() },
      confirm: { _ in change() }
    )
  }

  /// The action named with the credential's everyday term.
  private var changeTitle: LocalizedStringKey {
    switch credential {
    case .pin1:
      "Change Basic PIN 1"

    case .pin2:
      "Change Signature PIN 2"
    }
  }

  private var changeButton: some View {
    Button {
      focus = nil
      pending = .change(role)
    } label: {
      Text(changeTitle)
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
        || !model.allowsCredentialOperation(spending: role)
        || model.cardOperationInProgress
    )
    .accessibilityIdentifier("managementChange\(credential.identifierName)")
  }

  /// The three secret fields, threaded for Return.
  @ViewBuilder private var entryRows: some View {
    CredentialSecretField(
      name: String(localized: "Current \(credential.everydayName)"),
      text: $current,
      revealIdentifier: "managementChange\(credential.identifierName)CurrentReveal",
      fieldIdentifier: "managementChange\(credential.identifierName)Current",
      field: {
        SecureField("Current \(credential.everydayName)", text: $current)
          .textContentType(.oneTimeCode)
          #if os(iOS)
            .keyboardType(.numberPad)
          #endif
          .onValueChange(of: current) { typed in
            current = LimitedDigits.pin(typed)
          }
          .focused($focus, equals: .current)
          .onSubmit { advance(from: .current) }
          .accessibilityIdentifier("managementChange\(credential.identifierName)Current")
      },
      validation: {
        CredentialValidationIndicator(
          valid: currentIsValid && !newPinMatchesCurrent,
          unchanged: newPinMatchesCurrent,
          isEmpty: current.isEmpty)
      }
    )
    CredentialSecretField(
      name: CredentialLabels.newPinField(for: role),
      text: $new,
      revealIdentifier: "managementChange\(credential.identifierName)NewReveal",
      fieldIdentifier: "managementChange\(credential.identifierName)New",
      field: {
        SecureField(CredentialLabels.newPinField(for: role), text: $new)
          .textContentType(.oneTimeCode)
          #if os(iOS)
            .keyboardType(.numberPad)
          #endif
          .onValueChange(of: new) { typed in
            new = LimitedDigits.pin(typed)
          }
          .focused($focus, equals: .new)
          .onSubmit { advance(from: .new) }
          .accessibilityIdentifier("managementChange\(credential.identifierName)New")
      },
      validation: {
        CredentialValidationIndicator(
          valid: newIsValid && !newPinMatchesCurrent,
          unchanged: newPinMatchesCurrent,
          isEmpty: new.isEmpty)
      }
    )
    CredentialSecretField(
      name: CredentialLabels.repeatPinField(for: role),
      text: $repeated,
      revealIdentifier: "managementChange\(credential.identifierName)RepeatReveal",
      fieldIdentifier: "managementChange\(credential.identifierName)Repeat",
      field: {
        SecureField(CredentialLabels.repeatPinField(for: role), text: $repeated)
          .textContentType(.oneTimeCode)
          #if os(iOS)
            .keyboardType(.numberPad)
          #endif
          .onValueChange(of: repeated) { typed in
            repeated = LimitedDigits.pin(typed)
          }
          .focused($focus, equals: .repeated)
          .onSubmit { advance(from: .repeated) }
          .accessibilityIdentifier("managementChange\(credential.identifierName)Repeat")
      },
      validation: {
        CredentialValidationIndicator(
          valid: repeatedIsValid && !newPinMatchesCurrent,
          entriesDiffer: entriesDiffer,
          unchanged: newPinMatchesCurrent,
          isEmpty: repeated.isEmpty)
      }
    )
  }

  /// Return advances; on the last field it submits when complete.
  private func advance(from field: Field) {
    switch field {
    case .current:
      focus = .new

    case .new:
      focus = .repeated

    case .repeated:
      // Return on the last field asks the same question the button
      // asks; a keyboard path that skipped it would be the fastest
      // way to spend the wrong counter.
      if isComplete {
        focus = nil
        pending = .change(role)
      }
    }
  }

  /// Runs the change and destroys every entry after the card responds.
  private func change() {
    guard isComplete, !model.cardOperationInProgress else { return }
    let currentEntry = current
    let newEntry = new
    clearEntries()
    Task {
      switch credential {
      case .pin1:
        _ = await model.changePin1(current: currentEntry, new: newEntry)

      case .pin2:
        _ = await model.changePin2(current: currentEntry, new: newEntry)
      }
    }
  }

  /// Destroys every secret entered for this operation.
  private func clearEntries() {
    current = ""
    new = ""
    repeated = ""
    focus = nil
  }
}
