// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

extension CardManagementView {
  // MARK: Nested Types

  /// The four things this window does to a credential in use.
  ///
  /// Each is one tab, named in full. The action and the credential
  /// are read together or not at all: a holder who means PIN 2 must
  /// not reach PIN 1, and must not have to make two choices to say
  /// one thing.
  ///
  /// Reset rather than unblock: the card resets the retry counter and
  /// takes a new value whether or not the credential was blocked, so
  /// someone who has forgotten a PIN does not have to exhaust it
  /// first to be allowed a new one.
  internal enum ManagementTask: CaseIterable, Equatable {
    case changePin1
    case changePin2
    case resetPin1
    case resetPin2

    // MARK: Computed Properties

    /// The tab's label, naming the action and the credential.
    internal var name: String {
      switch self {
      case .changePin1:
        String(localized: "Change Basic PIN 1")

      case .changePin2:
        String(localized: "Change Signature PIN 2")

      case .resetPin1:
        String(localized: "Reset Basic PIN 1")

      case .resetPin2:
        String(localized: "Reset Signature PIN 2")
      }
    }

    /// Accessibility identifier used for test automation.
    internal var accessibilityIdentifier: String {
      switch self {
      case .changePin1:
        "managementTask.changePin1"

      case .changePin2:
        "managementTask.changePin2"

      case .resetPin1:
        "managementTask.resetPin1"

      case .resetPin2:
        "managementTask.resetPin2"
      }
    }
  }
}
