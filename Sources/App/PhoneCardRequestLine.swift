// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// The line that asks for the paired phone's card.
internal struct PhoneCardRequestLine: View {
  internal let request: PhoneCardRequest

  internal var body: some View {
    Text(Self.instruction(for: request))
      .foregroundStyle(.secondary)
  }

  /// The words that ask for the card, in the user's language.
  nonisolated internal static func instruction(for request: PhoneCardRequest) -> String {
    switch request {
    case .insertIntoPhoneReader:
      String(localized: "Insert the card into the phone's card reader.")

    case .placeOnPhone:
      String(localized: "Place the card on the phone.")
    }
  }
}
