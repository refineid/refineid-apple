// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation

  /// The visible mark placed on a signed PDF.
  internal enum DocumentStampStyle: String, CaseIterable, Sendable {
    /// The portrait carrying a card-signed QR attestation.
    case portraitQr = "portrait-qr"

    /// Handwriting on a line, followed by the certificate name and SATU.
    case signatureAndIdentity = "signature-and-identity"

    /// The restrained mark used until the portrait experiment was added.
    internal static let standard = Self.signatureAndIdentity

    /// The preference holding an explicit non-default choice.
    private static let preferenceKey = "documentStampStyle"

    /// Whether signing needs the larger DG2 portrait read.
    internal var readsPortrait: Bool { false }

    /// The selected style, or the standard when nothing was chosen.
    internal static func load() -> Self {
      load(from: .standard)
    }

    /// The selection stored in the supplied preference domain.
    internal static func load(from preferences: UserDefaults) -> Self {
      guard
        let rawValue = preferences.string(forKey: Self.preferenceKey),
        let style = Self(rawValue: rawValue)
      else {
        return Self.standard
      }
      return style
    }

    /// Persists an explicit choice; the standard occupies no preference.
    internal static func save(_ style: Self) {
      save(style, to: .standard)
    }

    /// Persists a choice in the supplied preference domain.
    internal static func save(_ style: Self, to preferences: UserDefaults) {
      if style == Self.standard {
        preferences.removeObject(forKey: Self.preferenceKey)
      } else {
        preferences.set(style.rawValue, forKey: Self.preferenceKey)
      }
    }
  }

#endif
