// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

@Suite("Contactless authorization publication")
internal struct OnDemandPinPublicationTests {
  @Test(
    "Stored contactless credentials have identical authorization policy in both modes",
    arguments: [false, true])
  internal func storedCredentialDoesNotAddNativeConstraint(experimentEnabled: Bool) {
    #expect(
      !OnDemandPinExperiment.requiresPasswordConstraint(
        isContactless: true,
        experimentEnabled: experimentEnabled,
        hasStoredCredential: true))
    #expect(
      OnDemandPinExperiment.needsSigningField(
        isRegistrationField: false,
        experimentEnabled: experimentEnabled,
        pinAvailable: true))
  }

  @Test("Missing credentials require native authorization only with on-demand entry")
  internal func missingCredentialPolicy() {
    #expect(
      OnDemandPinExperiment.requiresPasswordConstraint(
        isContactless: true, experimentEnabled: true, hasStoredCredential: false))
    #expect(
      !OnDemandPinExperiment.requiresPasswordConstraint(
        isContactless: true, experimentEnabled: false, hasStoredCredential: false))
    #expect(
      OnDemandPinExperiment.requiresPasswordConstraint(
        isContactless: false, experimentEnabled: false, hasStoredCredential: true))
  }

}
