// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineID

@Suite("Local web signing opt-in")
@MainActor
internal struct ScsServiceTests {
  @Test("Fresh settings never start the server or its identity creation")
  internal func disabledByDefault() throws {
    let name = "fi.refineid.tests.scs." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    var starts = 0
    var stops = 0
    let service = ScsService(defaults: defaults, start: { starts += 1 }, stop: { stops += 1 })
    service.restore()
    service.setEnabled(false)
    #expect(!service.isEnabled)
    #expect(starts == 0)
    #expect(stops == 0)
  }

  @Test("Opt-in persists, restores once, and disabling stops the service")
  internal func persistedLifecycle() throws {
    let name = "fi.refineid.tests.scs." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    var starts = 0
    var stops = 0
    let service = ScsService(defaults: defaults, start: { starts += 1 }, stop: { stops += 1 })
    service.setEnabled(true)
    service.setEnabled(true)
    service.restore()
    #expect(starts == 1)
    #expect(defaults.bool(forKey: AppSettings.scsEnabled))
    let restored = ScsService(defaults: defaults, start: { starts += 1 }, stop: { stops += 1 })
    #expect(restored.isEnabled)
    restored.restore()
    restored.restore()
    #expect(starts == 2)
    restored.setEnabled(false)
    restored.setEnabled(false)
    #expect(stops == 1)
    #expect(!defaults.bool(forKey: AppSettings.scsEnabled))
    let disabled = ScsService(defaults: defaults, start: { starts += 1 }, stop: { stops += 1 })
    disabled.restore()
    #expect(starts == 2)
    service.setEnabled(false)
    service.setEnabled(true)
    #expect(starts == 3)
  }
}
