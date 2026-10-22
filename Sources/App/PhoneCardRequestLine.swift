// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// The line that asks for the paired phone's card.
internal struct PhoneCardRequestLine: View {
  internal let request: PhoneCardRequest

  internal var body: some View {
    Group {
      switch request {
      case .insertIntoPhoneReader:
        Text("Insert the card into the phone's card reader.")

      case .placeOnPhone:
        Text("Place the card on the phone.")
      }
    }
    .foregroundStyle(.secondary)
  }
}
