// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// View providing share action for a loaded card photo.
internal struct CardIdentityPhotoActionsView: View {
  // MARK: - Properties

  internal let holder: String
  internal let photoData: Data?

  // MARK: - Body

  internal var body: some View {
    if let photoUrl = CardPhotoStore.photoFileURL(for: holder) {
      ShareLink(item: photoUrl) {
        Label(
          String(localized: "identity.sharePhoto", defaultValue: "Share photo"),
          systemImage: "square.and.arrow.up"
        )
      }
      .buttonStyle(.bordered)
      .accessibilityIdentifier("shareCardPhotoButton")
    }
  }

  // MARK: - Initializers

  internal init(holder: String, photoData: Data?) {
    self.holder = holder
    self.photoData = photoData
  }
}
