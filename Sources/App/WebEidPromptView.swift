// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import SwiftUI

  /// Native macOS prompt shown when Safari requests a Web eID login,
  /// signing certificate, or document-hash signature.
  internal struct WebEidPromptView: View {
    // MARK: Nested Types

    private enum Layout {
      static let contentWidth: CGFloat = 420
      static let sectionSpacing: CGFloat = 14
      static let headerSpacing: CGFloat = 4
      static let fieldSpacing: CGFloat = 6
      static let cardPadding: CGFloat = 12
      static let cornerRadius: CGFloat = 10
      static let outerPadding: CGFloat = 20
      static let warningBorderOpacity: Double = 0.45
      static let fieldHeight: CGFloat = 28
    }

    // MARK: Properties

    @Bindable internal var model: WebEidPromptModel
    @FocusState private var pinFieldFocused: Bool
    @Environment(\.controlActiveState)
    private var controlActiveState

    // MARK: Content Properties

    internal var body: some View {
      VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
        headerSection
        cardSection
        if let message = model.errorMessage {
          errorBanner(message)
        }
        if model.requiredRole != nil, case .ready = model.cardState, !model.isOperationBlocked {
          pinEntrySection
        }
        buttonRow
      }
      .padding(Layout.outerPadding)
      .frame(width: Layout.contentWidth)
      .writingToolsBehavior(.disabled)
      .task(id: focusTrigger) {
        guard controlActiveState == .key, shouldFocusPinField else { return }
        await InitialFieldFocus.settle()
        pinFieldFocused = true
      }
    }

    private var shouldFocusPinField: Bool {
      if case .ready = model.cardState, model.requiredRole != nil, !model.isOperationBlocked {
        return true
      }
      return false
    }

    private var focusTrigger: String {
      "\(controlActiveState == .key)-\(shouldFocusPinField)"
    }

    private var headerSection: some View {
      VStack(alignment: .leading, spacing: Layout.headerSpacing) {
        Text(model.windowTitle)
          .font(.headline)
        Text(verbatim: model.originText)
          .font(.subheadline.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
    }

    @ViewBuilder private var cardSection: some View {
      switch model.cardState {
      case .loading:
        HStack {
          ProgressView()
            .controlSize(.small)
          Text("Reading card…")
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.cardPadding)
        .background(
          .quaternary.opacity(Layout.warningBorderOpacity),
          in: RoundedRectangle(cornerRadius: Layout.cornerRadius))

      case .waitingForCard:
        Text("Insert your ID card into the reader.")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(Layout.cardPadding)
          .background(
            .quaternary.opacity(Layout.warningBorderOpacity),
            in: RoundedRectangle(cornerRadius: Layout.cornerRadius))

      case .ready(let preview):
        HStack {
          Image(systemName: "person.text.rectangle")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
          Text(verbatim: preview.holderName)
            .font(.body.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.cardPadding)
        .background(
          .quaternary.opacity(Layout.warningBorderOpacity),
          in: RoundedRectangle(cornerRadius: Layout.cornerRadius))

      case .unavailable(let reason):
        errorBanner(reason)
      }
    }

    @ViewBuilder private var pinEntrySection: some View {
      if let role = model.requiredRole {
        VStack(alignment: .leading, spacing: Layout.fieldSpacing) {
          Text(CredentialLabels.entryPrompt(for: role, bundle: .main))
            .font(.subheadline)
          pinInputBox(for: role)
        }
      }
    }

    private var buttonRow: some View {
      HStack {
        Spacer()
        Button(String(localized: "Cancel")) {
          model.cancel()
        }
        .keyboardShortcut(.cancelAction)

        Button {
          model.submit()
        } label: {
          if model.isSubmitting {
            ProgressView()
              .controlSize(.small)
          } else {
            Text(model.confirmButtonTitle)
          }
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(!model.canSubmit)
      }
    }

    private func pinInputBox(for role: CredentialRole) -> some View {
      let pinBinding = Binding(
        get: { model.pinDigits },
        set: { model.limitPinEntry($0) }
      )
      return CredentialSecretField(
        name: CredentialLabels.name(for: role),
        text: pinBinding,
        revealIdentifier: "web-eid-pin-reveal",
        fieldIdentifier: "web-eid-pin-field"
      ) {
        SecureField(CredentialLabels.name(for: role), text: pinBinding)
          .focused($pinFieldFocused)
          .onSubmit {
            if model.canSubmit {
              model.submit()
            }
          }
      } validation: {
        EmptyView()
      }
      .frame(minHeight: Layout.fieldHeight)
      .padding(.horizontal, Layout.cardPadding)
      .background(
        RoundedRectangle(cornerRadius: Layout.cornerRadius)
          .stroke(.separator)
      )
    }

    private func errorBanner(_ message: String) -> some View {
      Text(message)
        .font(.callout)
        .foregroundStyle(.orange)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(Layout.cardPadding)
        .overlay(
          RoundedRectangle(cornerRadius: Layout.cornerRadius)
            .stroke(.orange.opacity(Layout.warningBorderOpacity))
        )
    }
  }

#endif
