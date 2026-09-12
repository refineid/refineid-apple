// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineID

/// The visible PDF stamp remains opt-in when it carries a portrait QR.
@Suite
internal struct DocumentStampStyleTests {
  private static func preferences() throws -> (String, UserDefaults) {
    let name = "DocumentStampStyleTests.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: name))
    preferences.removePersistentDomain(forName: name)
    return (name, preferences)
  }

  @Test
  internal func noPreferenceUsesSignatureNameAndSatu() throws {
    let (name, preferences) = try Self.preferences()
    defer { preferences.removePersistentDomain(forName: name) }

    #expect(
      DocumentStampStyle.load(from: preferences) == .signatureAndIdentity
    )
    #expect(!DocumentStampStyle.load(from: preferences).readsPortrait)
  }

  @Test
  internal func portraitQrIsAnExplicitPersistentChoice() throws {
    let (name, preferences) = try Self.preferences()
    defer { preferences.removePersistentDomain(forName: name) }

    DocumentStampStyle.save(.portraitQr, to: preferences)

    #expect(DocumentStampStyle.load(from: preferences) == .portraitQr)
    #expect(DocumentStampStyle.load(from: preferences).readsPortrait)
  }

  @Test
  internal func restoringTheStandardRemovesTheOverride() throws {
    let (name, preferences) = try Self.preferences()
    defer { preferences.removePersistentDomain(forName: name) }
    DocumentStampStyle.save(.portraitQr, to: preferences)

    DocumentStampStyle.save(.signatureAndIdentity, to: preferences)

    #expect(
      DocumentStampStyle.load(from: preferences) == .signatureAndIdentity
    )
  }
}
