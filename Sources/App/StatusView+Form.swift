// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  extension StatusView {
    private static let formInset: CGFloat = 20
    internal static let readySpacing: CGFloat = 10

    private static let actionGapCount: CGFloat = 2
    private static let actionGapAdjustment = (padding + formInset) / actionGapCount - readySpacing

    internal static var centeredActionTopPadding: CGFloat {
      readySpacing + actionGapAdjustment
    }

    @ViewBuilder internal var statusForm: some View {
      if showsReadySection || showsStandaloneReading {
        VStack(spacing: Self.readySpacing) {
          if showsStandaloneReading {
            identityBox(for: .cardWithoutIdentity)
          } else {
            statusRow(showsIdentity: documentControls.showsIdentity)
            if documentControls.showsIdentity,
              showsSafariExtensionNotice,
              StatusMessage(signingModel) == nil
            {
              safariExtensionNotice
            }
            if documentControls.showsIdentity,
              signingBlockedByInitialPin2,
              StatusMessage(signingModel) == nil
            {
              pin2ChangeNotice
            }
          }
          if showsStandaloneReading ? !signingModel.queued.isEmpty : documentControls.showsDocuments
          {
            documentSection
          }
          if showsReadySection {
            readySection
          }
        }
        .padding([.horizontal, .top], Self.formInset)
        .padding(
          .bottom,
          showsReadySection && !documentControls.actions.isEmpty
            ? Self.formInset - Self.actionGapAdjustment : Self.formInset)
      } else {
        groupedForm
      }
    }

    internal var showsReadySection: Bool {
      #if FEATURE_CONTACTLESS
        !showsContactlessEntry
          && !activation.awaitsActivation && !activation.isReading && !shouldShowPairingPrompt
      #else
        !activation.awaitsActivation && !activation.isReading && !shouldShowPairingPrompt
      #endif
    }

    internal var showsStandaloneReading: Bool {
      #if FEATURE_CONTACTLESS
        if showsContactlessEntry { return false }
      #endif
      return activation.isReading && !activation.awaitsActivation
    }

    internal var panelOutline: some View {
      RoundedRectangle(cornerRadius: Self.readySpacing).strokeBorder(.secondary)
        .allowsHitTesting(false)
    }

    internal var safariExtensionNotice: some View {
      VStack(spacing: Self.readySpacing) {
        Text(
          "Enable the RefineID Web eID extension in Safari to log in with an Estonian ID card."
        )
        .foregroundStyle(.orange)
        .multilineTextAlignment(.center)
        Button("Open Safari Settings…") {
          safariExtensionStatus.openPreferences()
        }
        .accessibilityIdentifier("openSafariExtensionSettings")
      }
      .frame(maxWidth: .infinity)
      .padding(Self.readySpacing)
      .overlay { panelOutline }
      .accessibilityIdentifier("safariExtensionDisabledNotice")
    }

    internal var pin2ChangeNotice: some View {
      Text("Change PIN 2 so you can sign documents.")
        .foregroundStyle(.orange)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: StatusDocumentSection.dropHeight)
        .padding(Self.readySpacing)
        .overlay { panelOutline }
        .accessibilityIdentifier("pin2ChangeRequiredNotice")
    }

    private var groupedForm: some View {
      Form {
        formBody
      }
      .formStyle(.grouped)
      .scrollBounceBehavior(.basedOnSize)
      .fixedSize(horizontal: false, vertical: true)
    }

    /// The form without the contactless entry: activation, reading,
    /// pairing prompt, or the ready section.
    @ViewBuilder internal var sharedFormBody: some View {
      if activation.awaitsActivation {
        activationSection
      } else if activation.isReading {
        readingSection
      } else if shouldShowPairingPrompt {
        pairingPromptSection
      }
    }
  }

#endif
