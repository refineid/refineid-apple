// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import SwiftUI

  /// The documents to sign: dropped or chosen from the file dialog.
  internal struct StatusDocumentSection: View {
    private static let dropHeight: CGFloat = 96
    private static let dropCornerRadius: CGFloat = 10
    private static let dropBorderWidth: CGFloat = 2

    internal let signing: SignDocumentModel
    @Binding internal var format: SignatureFormat
    /// Whether the drop area invites signing as well as verifying.
    internal let offersSigning: Bool
    internal let onChoose: () -> Void
    internal let onAccept: ([URL]) -> Bool
    @State private var isTargeted = false

    internal var body: some View {
      Section {
        dropContents
          .frame(maxWidth: .infinity)
          .contentShape(.rect)
          .overlay {
            if isTargeted {
              RoundedRectangle(cornerRadius: Self.dropCornerRadius)
                .strokeBorder(.tint, lineWidth: Self.dropBorderWidth)
            }
          }
          .dropDestination(for: URL.self) { urls, _ in
            onAccept(urls)
          } isTargeted: { targeted in
            isTargeted = targeted
          }
          .accessibilityLabel(
            offersSigning ? Text("Documents to sign") : Text("Documents to verify")
          )
          .accessibilityValue(StatusView.pileValue(signing.queued))
          .accessibilityIdentifier("documentDropArea")
      }
    }

    @ViewBuilder private var dropContents: some View {
      if signing.queued.isEmpty {
        SignDropInvitation(targeted: isTargeted, offersSigning: offersSigning) { onChoose() }
          .frame(maxWidth: .infinity, minHeight: Self.dropHeight)
      } else {
        SignDocumentPile(
          documents: signing.queued,
          remove: { document in
            signing.remove(document)
            format = StatusView.sharedFormat(for: signing.queued)
          },
          add: { onChoose() },
          clear: { signing.clear() }
        )
      }
    }
  }

#endif
