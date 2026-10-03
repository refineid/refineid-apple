// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// Row providing copy and share actions for a loaded card photo.
internal struct CardIdentityPhotoActionsView: View {
  // MARK: - Constants

  private static let buttonSpacing: CGFloat = 12
  // Two seconds is long enough to notice without leaving stale feedback.
  private static let feedbackDuration: Duration =
    .seconds(1) + .seconds(1)

  // MARK: - Properties

  internal let holder: String
  internal let photoData: Data?

  @State private var copiedNotice = false

  // MARK: - Body

  internal var body: some View {
    HStack(spacing: Self.buttonSpacing) {
      Button {
        copyPhoto()
      } label: {
        Label(
          copiedNotice
            ? String(localized: "identity.photoCopied", defaultValue: "Copied")
            : String(localized: "identity.copyPhoto", defaultValue: "Copy photo"),
          systemImage: copiedNotice ? "checkmark" : "doc.on.doc"
        )
      }
      .accessibilityIdentifier("copyCardPhotoButton")

      if let photoUrl = CardPhotoStore.photoFileURL(for: holder) {
        ShareLink(item: photoUrl) {
          Label(
            String(localized: "identity.sharePhoto", defaultValue: "Share photo"),
            systemImage: "square.and.arrow.up"
          )
        }
        .accessibilityIdentifier("shareCardPhotoButton")
      }
    }
    .buttonStyle(.bordered)
  }

  // MARK: - Initializers

  internal init(holder: String, photoData: Data?) {
    self.holder = holder
    self.photoData = photoData
  }

  // MARK: - Methods

  private func copyPhoto() {
    #if canImport(UIKit)
      if let data = photoData, let uiImage = UIImage(data: data) {
        UIPasteboard.general.image = uiImage
        withAnimation {
          copiedNotice = true
        }
        Task {
          try? await Task.sleep(for: Self.feedbackDuration)
          await MainActor.run {
            withAnimation {
              copiedNotice = false
            }
          }
        }
      }
    #elseif canImport(AppKit)
      if let data = photoData, let nsImage = NSImage(data: data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([nsImage])
        withAnimation {
          copiedNotice = true
        }
        Task {
          try? await Task.sleep(for: Self.feedbackDuration)
          await MainActor.run {
            withAnimation {
              copiedNotice = false
            }
          }
        }
      }
    #endif
  }
}
