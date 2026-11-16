// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  extension StatusView {
    @ViewBuilder internal var statusForm: some View {
      Form {
        formBody
      }
      .formStyle(.grouped)
      // A form is a scroll view; one that fits its window stays still.
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
