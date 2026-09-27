// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// Human-facing credential names, shared by fields and prompts.
internal enum CredentialLabels {
  internal static func name(for role: CredentialRole) -> String {
    name(for: role, bundle: .main)
  }

  internal static func name(for role: CredentialRole, bundle: Bundle) -> String {
    switch role {
    case .pin1:
      String(localized: "Basic (PIN 1)", bundle: bundle)
    case .pin2:
      String(localized: "Signature (PIN 2)", bundle: bundle)
    case .puk:
      String(localized: "PUK", bundle: bundle)
    }
  }

  internal static func entryPrompt(for role: CredentialRole, bundle: Bundle) -> String {
    let name = name(for: role, bundle: bundle)
    return String(localized: "Enter \(name)", bundle: bundle)
  }
}
