// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) || os(macOS)

  import CardCore
  import SwiftUI

  /// The virtual card PIN 1, PIN 2, and PUK credential values and retry counters.
  internal struct VirtualIDCardCredentialsSection: View {
    // MARK: Nested Types

    /// The unchanging labels of one PIN/PUK credential row.
    private struct CredentialFieldSpec {
      fileprivate let title: String
      fileprivate let identifier: String
      fileprivate let valueLabel: String
      fileprivate let attemptsLabel: String
    }

    private static let minimumAttempts = 0

    // MARK: Properties

    @Binding internal var draft: VirtualIDCard.Snapshot

    // MARK: Content Properties

    internal var body: some View {
      pin1Credentials
      pin2Credentials
      pukCredentials
    }

    @ViewBuilder private var pin1Credentials: some View {
      credentialSection(
        CredentialFieldSpec(
          title: virtualCardLocalized("credential.pin1", defaultValue: "Basic PIN 1"),
          identifier: "virtualCardPIN1",
          valueLabel: virtualCardLocalized(
            "credential.pin1Value",
            defaultValue: "Basic PIN 1 value"),
          attemptsLabel: virtualCardLocalized(
            "credential.pin1Attempts",
            defaultValue: "Basic PIN 1 attempts")),
        value: $draft.card.pin1.value,
        attempts: attemptsBinding(\.pin1))
    }

    @ViewBuilder private var pin2Credentials: some View {
      credentialSection(
        CredentialFieldSpec(
          title: virtualCardLocalized("credential.pin2", defaultValue: "Signature PIN 2"),
          identifier: "virtualCardPIN2",
          valueLabel: virtualCardLocalized(
            "credential.pin2Value",
            defaultValue: "Signature PIN 2 value"),
          attemptsLabel: virtualCardLocalized(
            "credential.pin2Attempts",
            defaultValue: "Signature PIN 2 attempts")),
        value: $draft.card.pin2.value,
        attempts: attemptsBinding(\.pin2))
    }

    @ViewBuilder private var pukCredentials: some View {
      credentialSection(
        CredentialFieldSpec(
          title: virtualCardLocalized("credential.puk", defaultValue: "PUK"),
          identifier: "virtualCardPUK",
          valueLabel: virtualCardLocalized(
            "credential.pukValue",
            defaultValue: "PUK value"),
          attemptsLabel: virtualCardLocalized(
            "credential.pukAttempts",
            defaultValue: "PUK attempts")),
        value: $draft.card.puk.value,
        attempts: attemptsBinding(\.puk))
    }

    // MARK: Content Methods

    private func credentialSection(
      _ spec: CredentialFieldSpec,
      value: Binding<String>,
      attempts: Binding<Int>
    ) -> some View {
      Section(spec.title) {
        TextField(spec.valueLabel, text: value, axis: .vertical)
          #if os(iOS)
            .keyboardType(.numberPad)
          #endif
          .virtualCardEditorField()
          .accessibilityIdentifier("\(spec.identifier)Value")
        Stepper(
          value: attempts,
          in: Self.minimumAttempts...Int(RetryCount.pristineAllowance)
        ) {
          LabeledContent(spec.attemptsLabel) {
            Text(String(attempts.wrappedValue))
          }
        }
        .accessibilityIdentifier("\(spec.identifier)Attempts")
        .accessibilityValue(
          Text(
            String.localizedStringWithFormat(
              virtualCardLocalized(
                "credential.attemptsRemaining",
                defaultValue: "%lld attempts remaining"),
              attempts.wrappedValue)))
      }
    }

    // MARK: Functions

    private func attemptsBinding(
      _ keyPath: WritableKeyPath<
        VirtualIDCard.CardState,
        VirtualIDCard.CredentialState
      >
    ) -> Binding<Int> {
      Binding(
        get: {
          Int(draft.card[keyPath: keyPath].attemptsRemaining)
        },
        set: { value in
          draft.card[keyPath: keyPath].attemptsRemaining = UInt8(value)
        })
    }
  }

#endif
