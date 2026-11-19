// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation
  import SwiftUI
  import Testing

  @testable import RefineIDTestHost

  extension MacVoiceOverJourneysTests {
    internal struct LocalizedScreenWords {
      internal let connectReader: String
      internal let dropInvitation: String
      internal let pinCodes: String
      internal let pileLabel: String
      internal let clear: String
    }

    private static func expectedWords(for language: String) -> LocalizedScreenWords {
      switch language {
      case "fi":
        LocalizedScreenWords(
          connectReader: "Liitä kortinlukija.",
          dropInvitation: "Pudota asiakirjat tähän allekirjoitettavaksi.",
          pinCodes: "PIN-koodit",
          pileLabel: "Allekirjoitettavat asiakirjat",
          clear: "Tyhjennä"
        )
      case "sv":
        LocalizedScreenWords(
          connectReader: "Anslut en kortläsare.",
          dropInvitation: "Släpp dokument här för att underteckna dem.",
          pinCodes: "PIN-koder",
          pileLabel: "Dokument att underteckna",
          clear: "Rensa"
        )
      default:
        LocalizedScreenWords(
          connectReader: "Connect a card reader.",
          dropInvitation: "Drop documents here to sign them.",
          pinCodes: "PIN Codes",
          pileLabel: "Documents to sign",
          clear: "Clear"
        )
      }
    }

    @Test("Document signing PIN 2 field and outcome rows are spoken")
    internal func documentSigningPinAndOutcomeJourneyIsSpoken() async {
      let firstDocument = URL(filePath: "/documents/Agreement.pdf")
      let secondDocument = URL(filePath: "/documents/Appendix.pdf")
      let signing = SignDocumentModel()
      signing.accept([firstDocument])
      _ = await Self.inspect(
        Form {
          StatusSignatureSection(
            signing: signing,
            format: .constant(.pades),
            accessNumber: .constant(""),
            target: .anyReader
          )
        }
      )

      let outcome = StatusMessage.outcome(notice: nil, signed: [firstDocument, secondDocument])
      let outcomeNodes = await Self.inspect(
        StatusMessageRow(message: outcome, acknowledge: Self.noOp))
      #expect(outcomeNodes.speaks(StatusMessage.savedSentence(count: SampleCount.twoDocuments)))
      #expect(!outcomeNodes.hasIdentifier("statusAcknowledge"))

      let failure = StatusMessage.failure("Signature PIN 2 is incorrect.\n4 attempts remaining.")
      let failureNodes = await Self.inspect(
        StatusMessageRow(message: failure, acknowledge: Self.noOp))
      #expect(failureNodes.speaks("Signature PIN 2 is incorrect."))
      #expect(failureNodes.speaks("4 attempts remaining."))
      #expect(!failureNodes.hasIdentifier("statusAcknowledge"))
    }

    @Test("Card activation takeover exposes headers, secret fields, and Activate Card action")
    internal func cardActivationJourneyExposesFieldsAndValidation() async {
      let demo = DemoMode.shared
      demo.activate(scenario: .factoryFreshReader)
      defer { demo.deactivate() }

      let model = CardManagementModel(
        transport: .reader,
        activationRequired: true,
        cardAccessNumber: nil,
        activation: demo.activation,
        activationNeeds: demo.activationNeeds,
        pinLengths: DemoMode.pinLengths
      )
      let nodes = await Self.inspect(
        Form {
          CardActivationSection(
            model: model,
            lengths: DemoMode.pinLengths,
            onActivated: Self.noOp
          )
        }
      )

      #expect(nodes.speaks("Activate Card"))
      #expect(nodes.speaks("Basic PIN 1"))
      #expect(nodes.speaks("Signature PIN 2"))
      #expect(nodes.hasIdentifier("managementActivationEntry") || nodes.speaks("Activation PIN"))
      #expect(nodes.hasIdentifier("managementActivationPin1") || nodes.speaks("New Basic PIN 1"))
      #expect(
        nodes.hasIdentifier("managementActivationPin1Repeat") || nodes.speaks("Repeat Basic PIN 1")
      )
      #expect(
        nodes.hasIdentifier("managementActivationPin2") || nodes.speaks("New Signature PIN 2")
      )
      #expect(
        nodes.hasIdentifier("managementActivationPin2Repeat")
          || nodes.speaks("Repeat Signature PIN 2")
      )
      #expect(
        nodes.containsDisabledControl(identifier: "managementActivate"),
        "Activate Card stays disabled while fields are empty"
      )
    }

    @Test("PIN Codes window exposes task selector and change and unblock forms")
    internal func pinCodesWindowJourneyExposesTasksAndForms() async {
      let demo = DemoMode.shared
      demo.activate(scenario: .activatedReader)
      defer { demo.deactivate() }

      let nodes = await Self.inspect(
        CardManagementView(
          readerCardIsPresent: true,
          activationRequired: false,
          cardAccessNumber: nil,
          activation: nil,
          activationNeeds: nil,
          pinLengths: DemoMode.pinLengths,
          onActivationSucceeded: nil
        )
      )

      #expect(
        nodes.hasIdentifier("managementChangePIN1Current")
          || nodes.speaks("Current Basic PIN 1")
      )
      #expect(nodes.hasIdentifier("managementChangePIN1New") || nodes.speaks("New Basic PIN 1"))
      #expect(
        nodes.hasIdentifier("managementChangePIN1Repeat") || nodes.speaks("Repeat Basic PIN 1")
      )
      #expect(nodes.containsDisabledControl(identifier: "managementChangePIN1"))

      let model = CardManagementModel(
        transport: .reader,
        activationRequired: false,
        cardAccessNumber: nil,
        activation: nil,
        activationNeeds: nil,
        pinLengths: DemoMode.pinLengths
      )
      let unblockNodes = await Self.inspect(
        Form {
          CredentialUnblockSection(
            model: model,
            target: .pin2,
            lengths: DemoMode.pinLengths
          )
        }
      )
      #expect(unblockNodes.hasIdentifier("managementResetPIN2Puk") || unblockNodes.speaks("PUK"))
      #expect(
        unblockNodes.hasIdentifier("managementResetPIN2New")
          || unblockNodes.speaks("New Signature PIN 2")
      )
      #expect(
        unblockNodes.hasIdentifier("managementResetPIN2Repeat")
          || unblockNodes.speaks("Repeat Signature PIN 2")
      )
      #expect(unblockNodes.containsDisabledControl(identifier: "managementResetPIN2"))
    }

    @Test("PIN Codes window retry counters and floor guidance speak their state")
    internal func pinCodesWindowRetryCountersAndFloorGuidanceSpeak() async throws {
      let four = try #require(RetryCount(attemptsRemaining: SampleCount.reducedRetries))
      let two = try #require(RetryCount(attemptsRemaining: SampleCount.lowRetries))
      let zero = try #require(RetryCount(attemptsRemaining: SampleCount.blockedRetries))
      let report = CredentialProbeReport(
        pin1: .remaining(four),
        pin2: .remaining(two),
        puk: .remaining(zero)
      )
      let readings = CardManagementView.readingsBelowFull(report)
      #expect(readings.count == SampleCount.credentialCount)

      let view = CardManagementView(
        readerCardIsPresent: true,
        activationRequired: false,
        cardAccessNumber: nil
      )
      let barNodes = await Self.inspect(view.attemptsBar(readings))
      let pin1Name = CredentialLabels.name(for: .pin1)
      let pin2Name = CredentialLabels.name(for: .pin2)
      let reducedSpoken = String(localized: "\(four.attemptsRemaining) attempts remaining")
      let lowSpoken = String(localized: "\(two.attemptsRemaining) attempts remaining - low")
      let blockedSpoken = String(localized: "blocked - unblock with the PUK")
      #expect(barNodes.speaks("Attempts left:"))
      #expect(
        barNodes.contains { node in
          node.spokenText.contains(pin1Name) && node.spokenText.contains(reducedSpoken)
        }
      )
      #expect(
        barNodes.contains { node in
          node.spokenText.contains(pin2Name) && node.spokenText.contains(lowSpoken)
        }
      )
      #expect(
        barNodes.contains { node in
          node.spokenText.contains("PUK") && node.spokenText.contains(blockedSpoken)
        }
      )

      let floorReason = "Only 2 attempts remaining. Unblock with the PUK."
      let floorNodes = await Self.inspect(
        Form {
          CardFormButton(
            title: "Change Basic PIN 1",
            identifier: "managementChangePIN1",
            enabled: false,
            blockedReason: floorReason,
            action: Self.noOp
          )
        }
      )
      #expect(floorNodes.speaks(floorReason))
    }

    @Test(
      "Every macOS MVP screen speaks localized labels in English, Finnish, and Swedish",
      arguments: ["en", "fi", "sv"]
    )
    internal func mvpScreensSpeakInEveryShippingLanguage(language: String) async {
      let words = Self.expectedWords(for: language)
      let demo = DemoMode.shared
      demo.activate(scenario: .absent)
      defer { demo.deactivate() }

      let absentNodes = await Self.inspect(StatusView(), localeIdentifier: language)
      #expect(absentNodes.speaks(words.connectReader), "\(language): \(words.connectReader)")

      demo.activate(scenario: .activatedReader)
      let readyNodes = await Self.inspect(StatusView(), localeIdentifier: language)
      #expect(readyNodes.speaks(words.dropInvitation), "\(language): \(words.dropInvitation)")
      #expect(
        readyNodes.containsSpokenControl(identifier: "pinCodesButton", spoken: words.pinCodes),
        "\(language): \(words.pinCodes)"
      )

      let document = URL(filePath: "/documents/Agreement.pdf")
      let pileNodes = await Self.inspect(
        SignDocumentPile(
          documents: [document],
          remove: Self.ignoreURL,
          add: Self.noOp,
          clear: Self.noOp
        ),
        localeIdentifier: language
      )
      #expect(pileNodes.speaks(words.pileLabel), "\(language): \(words.pileLabel)")
      #expect(pileNodes.speaks(words.clear), "\(language): \(words.clear)")
    }
  }

#endif
