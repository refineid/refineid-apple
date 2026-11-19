// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  extension StatusView {
    private static let formInset: CGFloat = 20
    internal static let readySpacing: CGFloat = 10

    @ViewBuilder internal var statusForm: some View {
      if (showsReadySection && signingModel.queued.isEmpty && signingModel.pending == nil)
        || showsStandaloneReading
      {
        VStack(spacing: Self.readySpacing) {
          if showsStandaloneReading {
            identityBox(for: .cardWithoutIdentity)
          } else {
            statusRow(showsIdentity: documentControls.showsIdentity)
          }
          if documentControls.showsDocuments, !showsStandaloneReading {
            idleDocumentArea
              .padding(Self.readySpacing)
              .overlay { panelOutline }
          }
        }
        .padding(Self.formInset)
      } else if showsReadySection {
        VStack(spacing: Self.readySpacing) {
          statusRow(showsIdentity: documentControls.showsIdentity)
            .padding(.horizontal, Self.formInset)
          groupedForm
        }
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

    private var panelOutline: some View {
      RoundedRectangle(cornerRadius: Self.readySpacing).strokeBorder(.secondary)
        .allowsHitTesting(false)
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
      } else {
        readySection
      }
    }
  }

#endif
