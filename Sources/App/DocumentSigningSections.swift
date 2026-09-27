// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import CardCore
  import Foundation
  import SwiftUI

  /// The signing form: documents, method, authorization, commit and outcome.
  ///
  /// Lives apart from DocumentSigningView so neither type outgrows the
  /// body-length gate. Everything it edits arrives as bindings; the signing
  /// operation itself stays with the view that owns the result.
  @MainActor
  internal struct DocumentSigningSections: View {
    private enum Layout {
      static let fileNameLines = 2
    }

    @Binding internal var inputs: [DocumentSigningView.Input]
    @Binding internal var format: SignatureFormat
    @Binding internal var pin2: String
    @Binding internal var importsDocuments: Bool
    internal let isSigning: Bool
    internal let canSign: Bool
    internal let pin2IsValid: Bool
    internal let requiresRequesterPIN2: Bool
    internal let message: String?
    internal let messageTone: CredentialOutcomeText.Tone
    internal let onCommit: () -> Void

    internal var body: some View {
      documentSection
      if !inputs.isEmpty {
        formatSection
        credentialSection
        actionSection
      }
      if let message {
        Section {
          CredentialOutcomeText(message: message, tone: messageTone)
            .accessibilityIdentifier("signingMessage")
        }
      }
    }

    /// The format a fresh set of inputs signs with.
    ///
    /// Only a single PDF keeps the current choice; anything else falls
    /// back to the package, mirroring what the view did inline before
    /// the sections moved here.

    private var documentSection: some View {
      Section(text("signing.section", "Documents")) {
        ForEach(inputs, id: \.inputID) { input in
          HStack {
            Image(systemName: input.isPDF ? "doc.richtext" : "doc")
              .accessibilityHidden(true)
            Text(input.name).lineLimit(Layout.fileNameLines)
            Spacer()
            Button(role: .destructive) {
              inputs.removeAll { $0.inputID == input.inputID }
              format = Self.normalizedFormat(format, for: inputs)
            } label: {
              Image(systemName: "minus.circle.fill")
                .accessibilityHidden(true)
            }
            .accessibilityLabel(
              text("signing.remove", "Remove document"))
          }
        }
        Button {
          importsDocuments = true
        } label: {
          Label(
            inputs.isEmpty
              ? text("signing.choose", "Choose documents")
              : text("signing.add", "Add documents"),
            systemImage: "doc.badge.plus")
        }
        .accessibilityIdentifier("signingChooseDocuments")
      }
    }

    @ViewBuilder private var formatSection: some View {
      if inputs.count == 1, inputs.first?.isPDF == true {
        Section(text("signing.format", "Signing method")) {
          Picker(selection: $format) {
            Text(text("format.pades", "Separately (PDF)"))
              .tag(SignatureFormat.pades)
            Text(text("format.asice", "As a package (ASiC-E)"))
              .tag(SignatureFormat.asice)
          } label: {
            EmptyView()
          }
          .labelsHidden()
          .pickerStyle(.inline)
        }
      }
    }

    @ViewBuilder private var credentialSection: some View {
      if requiresRequesterPIN2 {
        Section(text("signing.authorization", "Signature authorization")) {
          CredentialSecretField(
            name: CredentialLabels.name(for: .pin2),
            text: $pin2,
            revealIdentifier: "signingPIN2Reveal",
            field: {
              SecureField(
                CredentialLabels.name(for: .pin2),
                text: $pin2
              )
              .keyboardType(.numberPad)
              .textContentType(.oneTimeCode)
              .accessibilityIdentifier("signingPIN2")
              .onValueChange(of: pin2) { value in
                pin2 = String(
                  value.filter(\.isNumber).prefix(Pin2.maximumDigitCount))
              }
            },
            validation: {
              if !pin2.isEmpty {
                Image(
                  systemName: pin2IsValid
                    ? "checkmark.circle.fill"
                    : "xmark.circle.fill"
                )
                .foregroundStyle(pin2IsValid ? .green : .red)
                .accessibilityHidden(true)
              }
            }
          )
        }
      }
    }

    private var actionSection: some View {
      Section {
        Button {
          onCommit()
        } label: {
          HStack {
            Spacer()
            if isSigning { ProgressView() }
            Text(
              isSigning
                ? text("signing.progress", "Signing")
                : inputs.count == 1
                  ? text("signing.commitOne", "Sign document")
                  : text("signing.commit", "Sign documents")
            )
            .bold()
            Spacer()
          }
        }
        .disabled(!canSign)
        .accessibilityIdentifier("signingCommit")
      }
    }

    internal static func normalizedFormat(
      _ current: SignatureFormat,
      for inputs: [DocumentSigningView.Input]
    ) -> SignatureFormat {
      guard inputs.count == 1, inputs.first?.isPDF == true else {
        return .asice
      }
      return current
    }

    private func text(
      _ key: StaticString,
      _ fallback: String.LocalizationValue
    ) -> String {
      String(localized: key, defaultValue: fallback, table: "DocumentSigning")
    }

  }
#endif
