// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import SwiftUI
  /// The signing configuration for ready documents.
  ///
  /// The format and the optional stamp; its action is in
  /// the button bar.
  internal struct StatusSignatureSection: View {
    internal let signing: SignDocumentModel
    @Binding internal var format: SignatureFormat
    @Binding internal var accessNumber: String
    /// Where the card operations go; nowhere while several cards wait
    /// for the holder's choice.
    internal let target: ReaderTarget

    /// Whether a card is there to type for.
    private var acceptsEntry: Bool {
      target != .unchosen
    }

    private var everyOneAPdf: Bool {
      !signing.queued.isEmpty && signing.queued.allSatisfy(SignatureFormat.isPdf)
    }

    internal var body: some View {
      if signing.pending != nil {
        Section {
          if everyOneAPdf {
            SignatureFormatRow(documents: signing.queued, format: $format)
          }
          #if FEATURE_PDF_STAMP
            if format == .pades, StampStore.isEnabled() {
              StampRow(signing: signing, accessNumber: $accessNumber)
                .disabled(!acceptsEntry)
            }
          #endif
        }
        .onChange(of: target) { used, _ in
          // What was typed or read belongs to the card used before.
          if case .slot = used, !signing.working {
            signing.cardRemoved()
            accessNumber = ""
          }
        }
      }
    }
  }

#endif
