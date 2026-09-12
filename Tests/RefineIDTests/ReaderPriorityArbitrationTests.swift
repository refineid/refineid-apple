// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import CryptoTokenKit
  import Foundation
  import Security
  import Testing

  @testable import RefineID

  /// When a physical card in a reader is connected, it has absolute priority
  /// over RAPP tokens, passive-states all wireless discovery, and withdraws
  /// remote identities.
  @Suite(.serialized)
  @MainActor
  internal struct ReaderPriorityArbitrationTests {
    @Test
    internal func readerCardPresenceSuppressesPublishing() throws {
      let initialPresence = CardPresence.shared.isReaderCardPresent
      defer {
        CardPresence.shared.setReaderCardPresentForTesting(initialPresence)
      }

      let signer = try SignerCertificateFixtures.makeSigner(for: .ecdsaSha256)
      CardPresence.shared.setReaderCardPresentForTesting(true)
      #expect(CardPresence.shared.isReaderCardPresent)

      // An attempt to publish while a reader card is present is suppressed.
      PersistentTokenRegistry.publish(certificateDER: signer.certificate)
      #expect(PersistentTokenRegistry.shared.certificateDER == nil)
    }

    @Test
    internal func readerCardPresenceWithdrawsActiveRemoteIdentity() {
      let initialPresence = CardPresence.shared.isReaderCardPresent
      defer {
        CardPresence.shared.setReaderCardPresentForTesting(initialPresence)
      }

      // Simulate a primed remote identity state
      PersistentTokenRegistry.shared.holderLine = "TEST HOLDER"
      PersistentTokenRegistry.shared.certificateDER = Data([0x30, 0x82, 0x01])
      PersistentTokenRegistry.shared.holderIsAdvertising = true
      PersistentTokenRegistry.shared.hasSeenHolderAdvertisement = true

      // Physical reader card inserted
      CardPresence.shared.setReaderCardPresentForTesting(true)

      #expect(PersistentTokenRegistry.shared.certificateDER == nil)
      #expect(PersistentTokenRegistry.shared.holderLine == nil)
      #expect(!PersistentTokenRegistry.shared.holderIsAdvertising)
      #expect(!PersistentTokenRegistry.shared.hasSeenHolderAdvertisement)
    }

    @Test
    internal func ensurePublishedWithdrawsWhenReaderCardPresent() {
      let initialPresence = CardPresence.shared.isReaderCardPresent
      defer {
        CardPresence.shared.setReaderCardPresentForTesting(initialPresence)
      }

      PersistentTokenRegistry.shared.certificateDER = Data([0x30, 0x82, 0x01])
      CardPresence.shared.setReaderCardPresentForTesting(true)

      PersistentTokenRegistry.shared.ensurePublished()
      #expect(PersistentTokenRegistry.shared.certificateDER == nil)
    }

    @Test
    internal func startWithdrawsWhenReaderCardPresent() {
      let initialPresence = CardPresence.shared.isReaderCardPresent
      defer {
        CardPresence.shared.setReaderCardPresentForTesting(initialPresence)
      }

      PersistentTokenRegistry.shared.certificateDER = Data([0x30, 0x82, 0x01])
      CardPresence.shared.setReaderCardPresentForTesting(true)

      PersistentTokenRegistry.shared.start()
      #expect(PersistentTokenRegistry.shared.certificateDER == nil)
    }

    @Test
    internal func startAfterPairingWithdrawsWhenReaderCardPresent() {
      let initialPresence = CardPresence.shared.isReaderCardPresent
      defer {
        CardPresence.shared.setReaderCardPresentForTesting(initialPresence)
      }

      PersistentTokenRegistry.shared.certificateDER = Data([0x30, 0x82, 0x01])
      CardPresence.shared.setReaderCardPresentForTesting(true)

      PersistentTokenRegistry.shared.startAfterPairing()
      #expect(PersistentTokenRegistry.shared.certificateDER == nil)
    }

    @Test
    internal func displacedRemoteCardConfigurationIDsIdentification() {
      let candidates = [
        "refineid-card-1234567890abcdef",
        "card-access-number",
        "refineid-rapp-card-aabbccddee112233",
        "other-driver-token",
      ]
      let displaced = DriverConfiguredCredentials.displacedRemoteCardConfigurationIDs(
        among: candidates
      )
      #expect(displaced == ["refineid-rapp-card-aabbccddee112233"])
    }

    @Test
    internal func makeKeychainItemsOnlyProducesAuthenticationItems() throws {
      let signer = try SignerCertificateFixtures.makeSigner(for: .ecdsaSha256)
      guard
        let certificate = SecCertificateCreateWithData(nil, signer.certificate as CFData),
        let profile = CardKeyProfile.resolve(fromCertificate: certificate)
      else {
        Issue.record("Failed to create certificate or resolve profile")
        return
      }

      let items = PersistentTokenRegistry.makeKeychainItems(for: certificate, profile: profile)
      let (certificateItem, keyItem) = try #require(items)

      #expect(certificateItem.label == String(localized: "Basic (PIN 1)"))
      #expect(keyItem.label == String(localized: "Basic (PIN 1)"))
      #expect(keyItem.canSign == true)
      #expect(keyItem.canDecrypt == false)
      #expect(keyItem.canPerformKeyExchange == false)
      #expect(keyItem.isSuitableForLogin == true)
      #expect((certificateItem.objectID as? String) == PersistentTokenIdentity.certificateObjectID)
      #expect((keyItem.objectID as? String) == PersistentTokenIdentity.keyObjectID)
    }

    @Test
    internal func readerCardDepartureRestoresPassiveState() {
      let initialPresence = CardPresence.shared.isReaderCardPresent
      defer {
        CardPresence.shared.setReaderCardPresentForTesting(initialPresence)
      }

      // Card inserted into reader
      CardPresence.shared.setReaderCardPresentForTesting(true)
      #expect(CardPresence.shared.isReaderCardPresent)

      // Card leaves reader
      CardPresence.shared.setReaderCardPresentForTesting(false)
      #expect(!CardPresence.shared.isReaderCardPresent)
    }

    @Test
    internal func makeKeychainItemsWithRsaProfileOmitsDecryption() throws {
      let signer = try SignerCertificateFixtures.makeSigner(for: .rsaSha256)
      guard
        let certificate = SecCertificateCreateWithData(nil, signer.certificate as CFData),
        let profile = CardKeyProfile.resolve(fromCertificate: certificate)
      else {
        Issue.record("Failed to create RSA certificate or resolve profile")
        return
      }

      let items = PersistentTokenRegistry.makeKeychainItems(for: certificate, profile: profile)
      let (certificateItem, keyItem) = try #require(items)

      #expect(keyItem.canSign == true)
      #expect(keyItem.canDecrypt == false)
      #expect(keyItem.canPerformKeyExchange == false)
      #expect(keyItem.isSuitableForLogin == true)
      #expect(certificateItem.label == String(localized: "Basic (PIN 1)"))
      #expect(keyItem.label == String(localized: "Basic (PIN 1)"))
    }

    @Test
    internal func pairingPromptInstructionLocalization() {
      let code = "123 456"
      let prompt = String(
        localized: "Open RefineID on phone (code \(code))."
      )
      #expect(prompt.contains(code))
      let readerPrompt = String(localized: "Insert card to reader")
      #expect(!readerPrompt.isEmpty)
    }
  }

#endif
