// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import AppKit
  import CardCore
  import SwiftUI

  extension StatusView {
    private static let pinPromptFieldWidth: CGFloat = 220
    private static let pinPromptFieldHeight: CGFloat = 24

    /// Prompts the user for PIN 2 modally.
    internal func promptForPin2() -> String? {
      let alert = NSAlert()
      alert.messageText = CredentialLabels.entryPrompt(for: .pin2, bundle: .main)
      alert.informativeText = String(localized: "Enter PIN 2 to sign the document.", bundle: .main)
      let field = NSSecureTextField(
        frame: NSRect(
          x: 0, y: 0, width: Self.pinPromptFieldWidth, height: Self.pinPromptFieldHeight)
      )
      alert.accessoryView = field
      alert.addButton(withTitle: String(localized: "Sign", bundle: .main))
      alert.addButton(withTitle: String(localized: "Cancel", bundle: .main))
      alert.window.initialFirstResponder = field

      while true {
        let response = alert.runModal()
        let digits = field.stringValue
        guard response == .alertFirstButtonReturn else {
          field.stringValue = ""
          return nil
        }
        guard Self.isEntryComplete(digits) else {
          NSSound.beep()
          continue
        }
        field.stringValue = ""
        return digits
      }
    }
  }

#endif
