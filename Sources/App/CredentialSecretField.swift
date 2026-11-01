// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import SwiftUI

/// A secret card-code row with one consistent, accessible reveal control.
///
/// The editable control is the caller's `SecureField` while hidden and a
/// standard `TextField` while revealed, so a revealed value supports
/// selection and copying. The revealed field keeps entries to ASCII
/// digits within the longest supported secret; the caller's own field
/// applies its exact bounds. The reveal button closes every row in one
/// column; its symbol names the action it offers, and an empty row stays
/// masked with the button disabled. The validation result sits before
/// it in a fixed slot, so neither the button nor the field moves when
/// the result appears.
internal struct CredentialSecretField<Field: View, Validation: View>: View {
  private let lineLimit = 1
  private let buttonSize = 44.0
  private let negativePadding = -10.0
  private let indicatorSize = 24.0

  // MARK: SwiftUI Properties

  @Binding private var text: String
  @State private var revealsValue = false

  // MARK: Properties

  private let name: String
  private let revealIdentifier: String
  private let fieldIdentifier: String?
  private let field: () -> Field
  private let validation: () -> Validation

  // MARK: Computed Properties

  private var revealAccessibilityLabel: String {
    let format =
      revealsValue
      ? String(localized: "Hide %@")
      : String(localized: "Show %@")
    return String.localizedStringWithFormat(format, name)
  }

  // MARK: Lifecycle

  // MARK: Content Properties

  /// The revealed field keeps the hidden field's identifier, so one
  /// stable name finds the value in either state.
  @ViewBuilder private var revealedField: some View {
    if let fieldIdentifier {
      revealedInput.accessibilityIdentifier(fieldIdentifier)
    } else {
      revealedInput
    }
  }

  private var revealedInput: some View {
    TextField(name, text: $text)
      .textContentType(.oneTimeCode)
      #if os(iOS)
        .keyboardType(.numberPad)
      #endif
      .autocorrectionDisabled()
      .lineLimit(lineLimit)
      .onValueChange(of: text) { value in
        text = LimitedDigits.puk(value)
      }
  }

  private var inputGroup: some View {
    Group {
      if revealsValue {
        revealedField
      } else {
        field()
      }
    }
    // A Form on macOS turns the field's title into a leading label
    // and shrinks the editable area to a small trailing box. The
    // plain, label-free field spans the whole line instead, with
    // the name shown inside it the way iOS shows it.
    #if os(macOS)
      .textFieldStyle(.plain)
      .labelsHidden()
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(alignment: .leading) {
        if text.isEmpty {
          Text(name)
          .foregroundStyle(.secondary)
          .allowsHitTesting(false)
        }
      }
    #endif
  }

  internal var body: some View {
    HStack {
      inputGroup
      validation()
        .frame(width: indicatorSize, height: indicatorSize)
      Button {
        revealsValue.toggle()
      } label: {
        // The eye is the field's state: closed while the digits are
        // hidden, open while they show.
        Image(systemName: revealsValue ? "eye" : "eye.slash")
      }
      .buttonStyle(.plain)
      .frame(width: buttonSize, height: buttonSize)
      .contentShape(Rectangle())
      .padding(negativePadding)
      .disabled(text.isEmpty)
      .accessibilityLabel(Text(verbatim: revealAccessibilityLabel))
      .accessibilityIdentifier(revealIdentifier)
    }
    .onValueChange(of: text) { value in
      if value.isEmpty {
        revealsValue = false
      }
    }
  }

  internal init(
    name: String,
    text: Binding<String>,
    revealIdentifier: String,
    @ViewBuilder field: @escaping () -> Field,
    @ViewBuilder validation: @escaping () -> Validation
  ) {
    self.init(
      name: name,
      text: text,
      revealIdentifier: revealIdentifier,
      fieldIdentifier: nil,
      field: field,
      validation: validation
    )
  }

  internal init(
    name: String,
    text: Binding<String>,
    revealIdentifier: String,
    fieldIdentifier: String?,
    @ViewBuilder field: @escaping () -> Field,
    @ViewBuilder validation: @escaping () -> Validation
  ) {
    self.name = name
    self._text = text
    self.revealIdentifier = revealIdentifier
    self.fieldIdentifier = fieldIdentifier
    self.field = field
    self.validation = validation
  }
}
