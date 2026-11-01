// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) || os(macOS)

  import CardCore
  import Foundation

  internal enum VirtualIDCardOverlayLocalization {
    private static let scenarioNames:
      [VirtualIDCard.Scenario: (key: StaticString, defaultValue: String.LocalizationValue)] = [
        .factoryFreshNearField: ("scenario.factoryFreshNearField", "Factory-fresh NFC card"),
        .legacyFactoryFreshNearField: (
          "scenario.legacyFactoryFreshNearField", "Factory-fresh legacy NFC card"
        ),
        .partialActivationNearField: (
          "scenario.partialActivationNearField", "Partially activated NFC card"
        ),
        .activatedNearField: ("scenario.activatedNearField", "Activated NFC card"),
        .registeredNearField: ("scenario.registeredNearField", "Registered NFC identity"),
        .factoryFreshReader: ("scenario.factoryFreshReader", "Factory-fresh reader card"),
        .activatedReader: ("scenario.activatedReader", "Activated reader card"),
        .pin1RecoveryReader: ("scenario.pin1RecoveryReader", "PIN 1 recovery with reader"),
        .pin2RecoveryReader: ("scenario.pin2RecoveryReader", "PIN 2 recovery with reader"),
        .pukRecoveryRefusedReader: (
          "scenario.pukRecoveryRefusedReader", "PUK recovery refused with reader"
        ),
        .absent: ("scenario.absent", "No card"),
      ]

    internal static func localizedText(
      _ key: StaticString,
      defaultValue: String.LocalizationValue
    ) -> String {
      String(
        localized: key,
        defaultValue: defaultValue,
        table: "VirtualIDCard")
    }

    internal static func scenarioName(_ scenario: VirtualIDCard.Scenario) -> String {
      guard let entry = scenarioNames[scenario] else {
        preconditionFailure("Missing scenario name")
      }
      return localizedText(entry.key, defaultValue: entry.defaultValue)
    }

    internal static func activationSchemeName(_ scheme: ActivationScheme) -> String {
      switch scheme {
      case .activationCodeIsPuk:
        localizedText(
          "activationScheme.activationCodeIsPuk",
          defaultValue: "Activation code is PUK")

      case .presetActivationPin:
        localizedText(
          "activationScheme.presetActivationPin",
          defaultValue: "Separate activation PIN")
      }
    }

    internal static func certificateStateName(_ state: VirtualIDCard.CertificateState) -> String {
      switch state {
      case .valid:
        localizedText("certificate.valid", defaultValue: "Valid")

      case .expired:
        localizedText("certificate.expired", defaultValue: "Expired")

      case .revoked:
        localizedText("certificate.revoked", defaultValue: "Revoked")

      case .unreadable:
        localizedText("certificate.unreadable", defaultValue: "Unreadable")

      case .missing:
        localizedText("certificate.missing", defaultValue: "Missing")
      }
    }

    internal static func faultPresetName(_ preset: VirtualIDCard.FaultPreset) -> String {
      switch preset {
      case .noFault:
        localizedText("fault.none", defaultValue: "None")

      case .nfcDisconnectBeforeConnection:
        localizedText(
          "fault.nfcDisconnectBeforeConnection",
          defaultValue: "NFC disconnects before connection")

      case .readerFailsCounterQuery:
        localizedText(
          "fault.readerFailsCounterQuery",
          defaultValue: "Reader fails retry counter query")

      case .cardRemovedDuringPINChange:
        localizedText(
          "fault.cardRemovedDuringPINChange",
          defaultValue: "Card removed during PIN change")

      case .cardRemovedDuringSignature:
        localizedText(
          "fault.cardRemovedDuringSignature",
          defaultValue: "Card removed during document signing")

      case .responseLostAfterPIN1Activation:
        localizedText(
          "fault.responseLostAfterPIN1Activation",
          defaultValue: "Response lost after PIN 1 activation")

      case .responseLostAfterPIN2Activation:
        localizedText(
          "fault.responseLostAfterPIN2Activation",
          defaultValue: "Response lost after PIN 2 activation")

      case .responseLostAfterSignature:
        localizedText(
          "fault.responseLostAfterSignature",
          defaultValue: "Response lost after document signing")

      case .certificateReadFailure:
        localizedText("fault.certificateReadFailure", defaultValue: "Certificate read failure")

      case .tokenPublicationFailure:
        localizedText("fault.tokenPublicationFailure", defaultValue: "Token publication failure")
      }
    }
  }

#endif
