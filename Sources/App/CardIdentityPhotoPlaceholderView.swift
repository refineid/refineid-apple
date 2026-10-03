// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// Placeholder view when no physical card photo has been read yet.
internal struct CardIdentityPhotoPlaceholderView: View {
  // MARK: - Constants

  private static let photoWidth: CGFloat = 130
  private static let photoHeight: CGFloat = 160
  private static let photoCornerRadius: CGFloat = 12
  private static let photoBorderOpacity: Double = 0.25
  private static let avatarSize: CGFloat = 48
  private static let placeholderSpacing: CGFloat = 8
  private static let placeholderBackgroundOpacity: Double = 0.1
  private static let borderWidth: CGFloat = 1
  private static let placeholderPadding: CGFloat = 4
  private static let holderLineLimit: Int = 2

  // MARK: - Properties

  internal let holder: String
  internal let isReadingPhoto: Bool

  // MARK: - Body

  internal var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: Self.photoCornerRadius)
        .fill(Color.secondary.opacity(Self.placeholderBackgroundOpacity))
        .frame(width: Self.photoWidth, height: Self.photoHeight)
        .overlay(
          RoundedRectangle(cornerRadius: Self.photoCornerRadius)
            .stroke(Color.secondary.opacity(Self.photoBorderOpacity), lineWidth: Self.borderWidth)
        )
      if isReadingPhoto {
        ProgressView()
      } else {
        VStack(spacing: Self.placeholderSpacing) {
          Image(systemName: "person.circle.fill")
            .font(.system(size: Self.avatarSize))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
          Text(holder)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(Self.holderLineLimit)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Self.placeholderPadding)
        }
        .frame(width: Self.photoWidth, height: Self.photoHeight)
      }
    }
  }

  // MARK: - Initializers

  internal init(holder: String, isReadingPhoto: Bool) {
    self.holder = holder
    self.isReadingPhoto = isReadingPhoto
  }
}
