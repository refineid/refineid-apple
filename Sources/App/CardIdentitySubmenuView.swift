// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// The identity submenu view displaying cardholder photo, details, and forget action.
internal struct CardIdentitySubmenuView: View {
  // MARK: - Constants

  private static let photoWidth: CGFloat = 130
  private static let photoHeight: CGFloat = 160
  private static let photoCornerRadius: CGFloat = 12
  private static let photoBorderOpacity: Double = 0.25
  private static let avatarSize: CGFloat = 48
  private static let placeholderSpacing: CGFloat = 8
  private static let cardSpacing: CGFloat = 12
  private static let placeholderBackgroundOpacity: Double = 0.1
  private static let borderWidth: CGFloat = 1
  private static let placeholderPadding: CGFloat = 4
  private static let holderLineLimit: Int = 2

  // MARK: - Properties

  internal let holder: String
  internal let identifier: String?
  internal let onForget: (() -> Void)?
  internal let onReadPhoto: (() async -> Data?)?

  @Environment(\.dismiss)
  private var dismiss

  @State private var photoData: Data?
  @State private var isReadingPhoto = false
  @State private var showsForgetConfirmation = false

  // MARK: - Body

  internal var body: some View {
    Form {
      photoSection
      detailsSection
      if let onForget {
        removeSection(action: onForget)
      }
    }
    .navigationTitle(String(localized: "Identity"))
    .onAppear {
      if photoData == nil {
        photoData = CardPhotoStore.getPhoto(for: holder)
      }
    }
  }

  // MARK: - Subviews

  private var photoSection: some View {
    Section {
      VStack(alignment: .center, spacing: Self.cardSpacing) {
        photoDisplayView
        readPhotoButton
      }
      .frame(maxWidth: .infinity)
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)
    }
  }

  @ViewBuilder private var photoDisplayView: some View {
    #if canImport(UIKit)
      if let data = photoData, let uiImage = UIImage(data: data) {
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFill()
          .frame(width: Self.photoWidth, height: Self.photoHeight)
          .clipShape(RoundedRectangle(cornerRadius: Self.photoCornerRadius))
          .overlay(
            RoundedRectangle(cornerRadius: Self.photoCornerRadius)
              .stroke(Color.secondary.opacity(Self.photoBorderOpacity), lineWidth: Self.borderWidth)
          )
          .accessibilityLabel(Text("Card photo"))
          .accessibilityIdentifier("cardPhotoView")
      } else {
        placeholderView
          .accessibilityIdentifier("cardPhotoPlaceholder")
      }
    #elseif canImport(AppKit)
      if let data = photoData, let nsImage = NSImage(data: data) {
        Image(nsImage: nsImage)
          .resizable()
          .scaledToFill()
          .frame(width: Self.photoWidth, height: Self.photoHeight)
          .clipShape(RoundedRectangle(cornerRadius: Self.photoCornerRadius))
          .overlay(
            RoundedRectangle(cornerRadius: Self.photoCornerRadius)
              .stroke(Color.secondary.opacity(Self.photoBorderOpacity), lineWidth: Self.borderWidth)
          )
          .accessibilityLabel(Text("Card photo"))
          .accessibilityIdentifier("cardPhotoView")
      } else {
        placeholderView
          .accessibilityIdentifier("cardPhotoPlaceholder")
      }
    #else
      placeholderView
        .accessibilityIdentifier("cardPhotoPlaceholder")
    #endif
  }

  private var readPhotoButton: some View {
    Button {
      readPhoto()
    } label: {
      Label(
        String(localized: "identity.readPhoto", defaultValue: "Read photo from card"),
        systemImage: "person.crop.square"
      )
    }
    .disabled(isReadingPhoto)
    .accessibilityIdentifier("readPhotoFromCardButton")
  }

  private var placeholderView: some View {
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

  private var detailsSection: some View {
    Section {
      LabeledContent(String(localized: "Person")) {
        Text(holder)
          .textSelection(.enabled)
          .accessibilityIdentifier("identityStatus")
      }
      if let identifier, !identifier.isEmpty {
        LabeledContent(
          String(localized: "identity.identifier", defaultValue: "Identifier")
        ) {
          Text(identifier)
            .textSelection(.enabled)
            .accessibilityIdentifier("identityIdentifier")
        }
      }
    }
  }

  // MARK: - Initializers

  internal init(
    holder: String,
    identifier: String?,
    onForget: (() -> Void)?,
    onReadPhoto: (() async -> Data?)?
  ) {
    self.holder = holder
    self.identifier = identifier
    self.onForget = onForget
    self.onReadPhoto = onReadPhoto
  }

  internal init(holder: String) {
    self.init(holder: holder, identifier: nil, onForget: nil, onReadPhoto: nil)
  }

  // MARK: - Methods

  private func removeSection(action: @escaping () -> Void) -> some View {
    Section {
      Button(role: .destructive) {
        showsForgetConfirmation = true
      } label: {
        Label {
          Text(String(localized: "identity.remove", defaultValue: "Remove identity from phone"))
        } icon: {
          Image(systemName: "person.badge.minus")
            .foregroundStyle(.red)
            .accessibilityHidden(true)
        }
      }
      .accessibilityIdentifier("forgetCardIdentityButton")
      .alert(
        "Forget identity?",
        isPresented: $showsForgetConfirmation
      ) {
        Button("Cancel", role: .cancel) {
          // Keep current identity
        }
        Button("Forget", role: .destructive) {
          action()
          dismiss()
        }
      }
    }
  }

  private func readPhoto() {
    guard !isReadingPhoto else { return }
    isReadingPhoto = true
    Task {
      if let onReadPhoto {
        if let data = await onReadPhoto() {
          CardPhotoStore.savePhoto(data, for: holder)
          await MainActor.run {
            photoData = data
            isReadingPhoto = false
          }
          return
        }
      }
      let sample = CardPhotoStore.syntheticSamplePhoto(name: holder)
      CardPhotoStore.savePhoto(sample, for: holder)
      await MainActor.run {
        photoData = sample
        isReadingPhoto = false
      }
    }
  }
}
