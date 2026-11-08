// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import SwiftUI

  /// The Mac's verification sheet: each waiting document with the facts
  /// of every signature it carries, and the trusted lists they were
  /// judged under.
  internal struct VerifyQueuedDocumentsView: View {
    // Large enough to show one whole signature without scrolling;
    // several documents scroll.
    private static let minimumWidth: CGFloat = 560
    private static let idealWidth: CGFloat = 640
    private static let minimumHeight: CGFloat = 600
    private static let idealHeight: CGFloat = 760
    private static let padding: CGFloat = 16

    internal let verification: QueuedDocumentVerification
    @ObservedObject private var trustedLists = TrustedListStore.shared
    @Environment(\.dismiss)
    private var dismiss

    internal var body: some View {
      VStack(spacing: 0) {
        Form {
          ForEach(verification.items, id: \.index) { item in
            VerifiedDocumentSections(name: item.document.lastPathComponent, model: item.model)
          }
          VerifyTrustedListsSection(trustedLists: trustedLists)
        }
        .formStyle(.grouped)
        HStack {
          Spacer()
          Button("Done") { dismiss() }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("verifyDone")
        }
        .padding(Self.padding)
      }
      .frame(
        minWidth: Self.minimumWidth, idealWidth: Self.idealWidth, maxWidth: .infinity,
        minHeight: Self.minimumHeight, idealHeight: Self.idealHeight, maxHeight: .infinity
      )
      // Opens at the ideal size and stays resizable.
      .presentationSizing(.fitted)
      .task { await trustedLists.refreshIfNeeded() }
      .onDisappear { verification.cancel() }
    }
  }

#endif
