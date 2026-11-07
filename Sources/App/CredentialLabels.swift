// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// Human-facing credential names, shared by fields and prompts.
///
/// Every label names the PIN in full with its number and no
/// parentheses, "Basic PIN 1" and "Signature PIN 2", as
/// `Documentation/design/ui.md` sets out.
internal enum CredentialLabels {
  internal static func name(for role: CredentialRole) -> String {
    name(for: role, bundle: .main)
  }

  internal static func name(for role: CredentialRole, bundle: Bundle) -> String {
    switch role {
    case .pin1:
      String(localized: "Basic PIN 1", bundle: bundle)
    case .pin2:
      String(localized: "Signature PIN 2", bundle: bundle)
    case .puk:
      String(localized: "PUK", bundle: bundle)
    }
  }

  /// The label of the field that takes the PIN in force.
  internal static func currentPinField(for role: CredentialRole) -> String {
    switch role {
    case .pin1:
      String(localized: "Current Basic PIN 1")
    case .pin2:
      String(localized: "Current Signature PIN 2")
    case .puk:
      name(for: role)
    }
  }

  /// The label of the field that takes a new PIN.
  internal static func newPinField(for role: CredentialRole) -> String {
    switch role {
    case .pin1:
      String(localized: "New Basic PIN 1")
    case .pin2:
      String(localized: "New Signature PIN 2")
    case .puk:
      name(for: role)
    }
  }

  /// The label of the field that repeats a new PIN.
  internal static func repeatPinField(for role: CredentialRole) -> String {
    switch role {
    case .pin1:
      String(localized: "Basic PIN 1 again")
    case .pin2:
      String(localized: "Signature PIN 2 again")
    case .puk:
      name(for: role)
    }
  }

  internal static func entryPrompt(for role: CredentialRole, bundle: Bundle) -> String {
    switch role {
    case .pin1:
      String(localized: "Enter Basic PIN 1", bundle: bundle)
    case .pin2:
      String(localized: "Enter Signature PIN 2", bundle: bundle)
    case .puk:
      String(localized: "Enter PUK", bundle: bundle)
    }
  }
}
