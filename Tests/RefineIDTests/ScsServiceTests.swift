// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

@testable import RefineIDTestHost

@Suite("Local web signing opt-in")
@MainActor
internal struct ScsServiceTests {
  @Test("Fresh settings never start the server or touch identity storage")
  internal func disabledByDefault() throws {
    let name = "fi.refineid.tests.scs." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    var starts = 0
    var stops = 0
    var removals = 0
    let controller = ScsOptInController(
      defaults: defaults,
      start: { starts += 1 },
      stop: { stops += 1 },
      removeIdentity: { removals += 1 }
    )
    controller.restore()
    controller.setEnabled(false)
    #expect(!controller.isEnabled)
    #expect(starts == 0)
    #expect(stops == 0)
    #expect(removals == 0)
  }

  @Test("Opt-in persists, restores once, and opt-out stops and removes identity")
  internal func persistedLifecycleAndOptOutCleanup() throws {
    let name = "fi.refineid.tests.scs." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    var starts = 0
    var stops = 0
    var removals = 0
    let controller = ScsOptInController(
      defaults: defaults,
      start: { starts += 1 },
      stop: { stops += 1 },
      removeIdentity: { removals += 1 }
    )
    controller.setEnabled(true)
    controller.setEnabled(true)
    controller.restore()
    #expect(starts == 1)
    #expect(defaults.bool(forKey: ScsOptInController.enabledKey))

    let restored = ScsOptInController(
      defaults: defaults,
      start: { starts += 1 },
      stop: { stops += 1 },
      removeIdentity: { removals += 1 }
    )
    #expect(restored.isEnabled)
    restored.restore()
    restored.restore()
    #expect(starts == 2)

    restored.setEnabled(false)
    restored.setEnabled(false)
    #expect(stops == 1)
    #expect(removals == 1)
    #expect(!defaults.bool(forKey: ScsOptInController.enabledKey))

    let disabled = ScsOptInController(
      defaults: defaults,
      start: { starts += 1 },
      stop: { stops += 1 },
      removeIdentity: { removals += 1 }
    )
    disabled.restore()
    #expect(starts == 2)
    #expect(removals == 1)
  }

  #if os(macOS) && FEATURE_SCS
    @Test("Disabling ScsService clears published status error, pending request, and notice")
    internal func scsServiceClearsPublishedStateOnDisable() throws {
      let name = "fi.refineid.tests.scs.service." + UUID().uuidString
      let defaults = try #require(UserDefaults(suiteName: name))
      defer { defaults.removePersistentDomain(forName: name) }
      var removals = 0
      let appService = ScsService(
        defaults: defaults,
        start: {
          // No-op in unit test.
        },
        stop: {
          // No-op in unit test.
        },
        removeIdentity: { removals += 1 }
      )
      appService.setEnabled(true)
      appService.setStatusError("port conflict")
      appService.setPendingRequest(origin: "https://dvv.fineid.fi")
      appService.setHolderNotice("PIN rejected (2 attempts remaining)")
      appService.setEnabled(false)
      #expect(appService.statusError == nil)
      #expect(appService.pendingRequestOrigin == nil)
      #expect(appService.holderNotice == nil)
      #expect(removals == 1)
    }
  #endif
}
