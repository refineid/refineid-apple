// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// Beside a form's button: why valid entries cannot go to the card.
///
/// A button that is off with nothing to fix in its fields says why, here
/// and in the words the refusal itself would use. Nothing is drawn while
/// an entry is still wrong, because the fields show that themselves.
internal struct CredentialBlockedReason: View {
  /// Whether every entry is valid.
  internal let entriesAreComplete: Bool

  /// The reason the card cannot be asked, or nil when it can.
  internal let reason: String?

  internal var body: some View {
    if entriesAreComplete, let reason {
      CredentialOutcomeText(message: reason, tone: .failure)
        .accessibilityIdentifier("managementBlockedReason")
    }
  }
}
