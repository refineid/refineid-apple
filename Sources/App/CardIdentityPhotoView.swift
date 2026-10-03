// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// The identity photo view displaying cardholder photo, placeholder, and card reading triggers.
internal struct CardIdentityPhotoView: View {
  // MARK: - Constants

  private static let photoWidth: CGFloat = 130
  private static let photoHeight: CGFloat = 160
  private static let photoCornerRadius: CGFloat = 12
  private static let photoBorderOpacity: Double = 0.25
  private static let cardSpacing: CGFloat = 12
  private static let borderWidth: CGFloat = 1

  // MARK: - Properties

  internal let holder: String
  internal let onReadPhoto: ((String?) async -> CardCredentialsView.CardPhotoReadResult)?

  @State private var photoData: Data?
  @State private var isReadingPhoto = false
  @State private var showingCanPrompt = false
  @State private var canInput = ""
  @State private var canPromptMessage = String(
    localized: "identity.canPromptMessage",
    defaultValue:
      "Enter the 6-digit Card Access Number (CAN) printed on the front of your card to read the photo."
  )
  @State private var showingErrorAlert = false
  @State private var errorMessage = ""

  // MARK: - Body

  internal var body: some View {
    Section {
      VStack(alignment: .center, spacing: Self.cardSpacing) {
        photoDisplayView
          .contentShape(Rectangle())
          .onTapGesture {
            readPhoto()
          }
          .accessibilityAddTraits(.isButton)
          .accessibilityHint(
            Text(
              String(
                localized: "identity.photoHint",
                defaultValue: "Double-tap to read photo from card"
              )))
        readPhotoButton
      }
      .frame(maxWidth: .infinity)
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)
    }
    .onAppear {
      if photoData == nil {
        photoData = CardPhotoStore.getPhoto(for: holder)
      }
    }
    .alert(
      String(localized: "identity.canPromptTitle", defaultValue: "Card Access Number"),
      isPresented: $showingCanPrompt
    ) {
      TextField(
        String(localized: "identity.canPlaceholder", defaultValue: "6-digit CAN"),
        text: $canInput
      )
      #if os(iOS)
        .keyboardType(.numberPad)
      #endif
      Button(String(localized: "identity.readPhoto", defaultValue: "Read photo from card")) {
        let trimmed = canInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == CardAccessNumber.digitCount {
          readPhoto(withCan: trimmed)
        } else {
          errorMessage = String(
            localized: "identity.invalidCanLength",
            defaultValue: "The Card Access Number must be exactly 6 digits."
          )
          showingErrorAlert = true
        }
      }
      Button(String(localized: "Cancel", defaultValue: "Cancel"), role: .cancel) {
        canInput = ""
      }
    } message: {
      Text(canPromptMessage)
    }
    .alert(
      String(localized: "identity.errorTitle", defaultValue: "Card Photo"),
      isPresented: $showingErrorAlert
    ) {
      Button(String(localized: "OK", defaultValue: "OK"), role: .cancel) {
        // Dismiss photo error alert
      }
    } message: {
      Text(errorMessage)
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
              .stroke(
                Color.secondary.opacity(Self.photoBorderOpacity),
                lineWidth: Self.borderWidth
              )
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
              .stroke(
                Color.secondary.opacity(Self.photoBorderOpacity),
                lineWidth: Self.borderWidth
              )
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
    CardIdentityPhotoPlaceholderView(holder: holder, isReadingPhoto: isReadingPhoto)
  }

  // MARK: - Initializers

  internal init(
    holder: String,
    onReadPhoto: ((String?) async -> CardCredentialsView.CardPhotoReadResult)?
  ) {
    self.holder = holder
    self.onReadPhoto = onReadPhoto
  }

  // MARK: - Methods

  private func readPhoto() {
    readPhoto(withCan: nil)
  }

  private func readPhoto(withCan can: String?) {
    guard !isReadingPhoto else { return }
    isReadingPhoto = true
    Task {
      guard let onReadPhoto else {
        await MainActor.run { isReadingPhoto = false }
        return
      }
      let result = await onReadPhoto(can)
      await MainActor.run {
        handlePhotoReadResult(result)
      }
    }
  }

  @MainActor
  private func handlePhotoReadResult(_ result: CardCredentialsView.CardPhotoReadResult) {
    isReadingPhoto = false
    switch result {
    case .success(let data):
      photoData = data
    case .cardAccessNumberRequired:
      promptForCan(rejected: false)
    case .wrongCardAccessNumber:
      promptForCan(rejected: true)
    case .cardUnavailable:
      showPhotoError(
        String(
          localized: "identity.cardUnavailableMessage",
          defaultValue:
            "No card detected. Please insert your card into the reader or hold it near your device."
        )
      )
    case .failed:
      showPhotoError(
        String(
          localized: "identity.readPhotoFailedMessage",
          defaultValue: "Could not read the photo from the card."
        )
      )
    }
  }

  @MainActor
  private func promptForCan(rejected: Bool) {
    if rejected {
      canPromptMessage = String(
        localized: "identity.wrongCanPromptMessage",
        defaultValue: """
          The Card Access Number was rejected by the card. \
          Please check the 6-digit CAN on the front of the card and try again.
          """
      )
    } else {
      canPromptMessage = String(
        localized: "identity.canPromptMessage",
        defaultValue:
          "Enter the 6-digit Card Access Number (CAN) printed on the front of your card to read the photo."
      )
    }
    canInput = ""
    showingCanPrompt = true
  }

  @MainActor
  private func showPhotoError(_ message: String) {
    errorMessage = message
    showingErrorAlert = true
  }
}
