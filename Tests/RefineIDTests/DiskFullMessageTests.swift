// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_REMOTE_CARD

  import CardCore
  import Foundation
  import Security
  import Testing

  @testable import RefineIDTestHost

  /// A write the system refused for lack of space says so, in the place the
  /// failed operation already reports; every other failure keeps its words.
  @Suite(.serialized)
  internal final class DiskFullMessageTests {
    private typealias Reason = RappPairingSearch<PairingEndpoint>.CloseReason

    private static let diskFull = String(
      localized: "The disk is full. Free some space and try again.")

    /// The catalog key of the full-disk sentence.
    private static let diskFullKey = "The disk is full. Free some space and try again."

    /// A fallback no full disk produces.
    private static let otherwise = "not a full disk"

    @Test
    internal func testAPairingStoredOutOfSpaceSaysTheDiskIsFull() {
      #expect(
        (RappPairingModel.failure(for: Reason.ceremonyEnded(.outOfSpace))?.message)
          == (Self.diskFull))
      #expect(
        (RappPairingModel.failure(for: Reason.ceremonyEnded(.protocolFailure))?.message)
          == (String(localized: "Pairing ended before it was completed.")))
    }

    @Test
    internal func testAPairingTheKeychainRefusedSaysItWasNotStoredWithTheCause() throws {
      let bare = String(localized: "The pairing could not be stored.")
      #expect(
        (RappPairingModel.failure(for: Reason.ceremonyEnded(.persistenceFailure(status: nil)))?
          .message) == (bare))
      let cause = try #require(SecCopyErrorMessageString(errSecMissingEntitlement, nil) as String?)
      let message = try #require(
        RappPairingModel.failure(
          for: Reason.ceremonyEnded(.persistenceFailure(status: errSecMissingEntitlement)))?.message
      )
      #expect((message) == (String(localized: "The pairing could not be stored. \(cause)")))
      #expect((message.hasSuffix(cause)))
    }

    @Test
    internal func testThePairingNotStoredSentenceIsSaidInEveryLanguage() throws {
      let catalog = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/App/Localizable.xcstrings")
      let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: catalog))
      let strings = try #require((json as? [String: Any])?["strings"] as? [String: Any])
      let expected = [
        ("fi", "Yhdistämistä ei voitu tallentaa."),
        ("sv", "Parkopplingen kunde inte sparas."),
      ]
      for (key, suffix) in [
        ("The pairing could not be stored.", ""), ("The pairing could not be stored. %@", " %@"),
      ] {
        let entry = try #require(strings[key] as? [String: Any])
        let localizations = try #require(entry["localizations"] as? [String: Any])
        for (language, value) in expected {
          let localization = try #require(localizations[language] as? [String: Any])
          let unit = try #require(localization["stringUnit"] as? [String: Any])
          #expect((unit["value"] as? String) == (value + suffix), "\(language)")
        }
      }
    }

    @Test
    internal func testACardAccessNumberRefusedForSpaceSaysTheDiskIsFull() {
      #expect((CardCredentialsModel.saveFailure(errSecDiskFull)) == (Self.diskFull))
      #expect((CardCredentialsModel.saveFailure(errSecIO)) == nil)
      #expect((CardCredentialsModel.saveFailure(errSecInteractionNotAllowed)) == nil)
    }

    @Test
    internal func testAVaultRefusedForSpaceSaysTheDiskIsFull() {
      #expect(
        (DiskFullMessage.message(
          for: RappDeviceVault.Failure.unavailable(errSecDiskFull), otherwise: Self.otherwise))
          == (Self.diskFull))
      #expect(
        (DiskFullMessage.message(
          for: RappDeviceVault.Failure.unavailable(errSecIO), otherwise: Self.otherwise))
          == (Self.otherwise))
    }

    @Test
    internal func testASignedDocumentWrittenOutOfSpaceSaysTheDiskIsFull() {
      #expect(
        (DocumentSigningMessage.message(for: CocoaError(.fileWriteOutOfSpace))) == (Self.diskFull))
      #expect((DocumentSigningMessage.message(for: POSIXError(.ENOSPC))) == (Self.diskFull))
      #expect(
        (DocumentSigningMessage.message(for: CocoaError(.fileWriteNoPermission))) != (Self.diskFull)
      )
    }

    @Test
    internal func testTheDiskFullSentenceIsSaidInEveryLanguage() throws {
      let catalog = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/App/Localizable.xcstrings")
      let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: catalog))
      let strings = try #require((json as? [String: Any])?["strings"] as? [String: Any])
      let entry = try #require(strings[Self.diskFullKey] as? [String: Any])
      let localizations = try #require(entry["localizations"] as? [String: Any])
      let expected = [
        ("fi", "Levy on täynnä. Vapauta tilaa ja yritä uudelleen."),
        ("sv", "Disken är full. Frigör utrymme och försök igen."),
      ]
      for (language, value) in expected {
        let localization = try #require(localizations[language] as? [String: Any])
        let unit = try #require(localization["stringUnit"] as? [String: Any])
        #expect((unit["value"] as? String) == (value), "\(language)")
      }
    }
  }
#endif
