// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

internal struct ContactlessCardKindTests {
  private enum Identity: Equatable {
    case personal
    case organization
  }

  @Test(arguments: [ContactlessCardKind.personal, .organization])
  internal func onlyTheSelectedStoreIsRead(kind: ContactlessCardKind) {
    var readPersonal = false
    var readOrganization = false
    let selected: Identity? = kind.select(
      personal: {
        readPersonal = true
        return .personal
      },
      organization: {
        readOrganization = true
        return .organization
      })
    #expect(readPersonal == (kind == .personal))
    #expect(readOrganization == (kind == .organization))
    #expect(selected == (kind == .personal ? .personal : .organization))
  }

  @Test(arguments: [ContactlessCardKind.personal, .organization])
  internal func missingSelectedIdentityNeverUsesTheOtherStore(kind: ContactlessCardKind) {
    let selected: Identity? = kind.select(
      personal: { kind == .personal ? nil : .personal },
      organization: { kind == .organization ? nil : .organization })
    #expect(selected == nil)
  }

  @Test
  internal func extensionReadsThePublishedSelection() throws {
    let name = "ContactlessCardKindTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    #expect(ContactlessCardKindStore.load(from: defaults) == .personal)
    ContactlessCardKindStore.save(.organization, to: defaults)
    #expect(ContactlessCardKindStore.load(from: defaults) == .organization)
    ContactlessCardKindStore.save(.personal, to: defaults)
    #expect(ContactlessCardKindStore.load(from: defaults) == .personal)
    #expect(ContactlessCardKindStore.load(from: nil) == .personal)
  }
}
