// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_REMOTE_CARD

  import CardCore
  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// What the requester tells its user when its search ends: the code is
  /// called not accepted only when every phone tried refused it, and a search
  /// that tried none says no phone in pairing mode was found (RAPP v26.11.8
  /// §4.2, "Trying Each Custodian in Pairing Mode" item 6), unless it found
  /// phones it could not reach.
  @Suite(.serialized)
  internal final class RappPairingSearchMessageTests {
    private typealias Reason = RappPairingSearch<PairingEndpoint>.CloseReason

    private static let notAccepted = String(localized: "The pairing code was not accepted.")

    #if os(macOS)
      private static let localNetworkDeniedMessage =
        String(
          localized: """
            macOS is blocking RefineID from the local network. Allow it in \
            System Settings › Privacy & Security › Local Network.
            """)

      private static let unreachableMessage =
        String(
          localized: """
            Could not connect to the phone. Check that the phone and this Mac \
            are on the same network and that RefineID is allowed to use the \
            local network.
            """)
    #else
      private static let localNetworkDeniedMessage =
        String(
          localized: """
            RefineID is not allowed to use the local network. Allow it in \
            Settings › Privacy & Security › Local Network.
            """)

      private static let unreachableMessage =
        String(
          localized: """
            Could not connect to the phone. Check that the phone and this \
            device are on the same network and that RefineID is allowed to \
            use the local network.
            """)
    #endif

    private static func assertTranslations(of key: String, finnish: String, swedish: String) throws
    {
      let catalog = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/App/Localizable.xcstrings")
      let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: catalog))
      let strings = try #require((json as? [String: Any])?["strings"] as? [String: Any])
      let entry = try #require(strings[key] as? [String: Any])
      let localizations = try #require(entry["localizations"] as? [String: Any])
      for (language, expected) in [("fi", finnish), ("sv", swedish)] {
        let localization = try #require(localizations[language] as? [String: Any])
        let unit = try #require(localization["stringUnit"] as? [String: Any])
        #expect((unit["value"] as? String) == (expected), "\(language)")
      }
    }

    @Test
    internal func testOnlyEveryRefusalIsAWrongCode() {
      #expect((RappPairingModel.failure(for: Reason.notAccepted)?.message) == (Self.notAccepted))
      let others: [Reason] = [
        .noneInPairingMode, .ceremonyEnded(.transportFailure), .ceremonyEnded(.protocolFailure),
      ]
      for reason in others {
        #expect((RappPairingModel.failure(for: reason)?.message) != (Self.notAccepted), "\(reason)")
      }
    }

    @Test
    internal func testASearchThatTriedNoPhoneSaysNoneWasFound() {
      #expect(
        (RappPairingModel.failure(for: Reason.noneInPairingMode)?.message)
          == (String(localized: "No phone in pairing mode was found.")))
    }

    @Test
    internal func testAPhoneFoundButUnreachedIsNotCalledMissing() {
      let missing = String(localized: "No phone in pairing mode was found.")
      #expect((RappPairingModel.failure(for: Reason.unreachable)) == (.unreachable))
      #expect((RappPairingModel.Failure.unreachable.message) != (missing))
      #expect((RappPairingModel.failure(for: Reason.localNetworkDenied)) == (.localNetworkDenied))
      let denied = RappPairingModel.Failure.localNetworkDenied.message
      #expect((denied) != (missing))
      #expect((denied) == (Self.localNetworkDeniedMessage))
    }

    @Test
    internal func testAnUnreachedPhoneSaysWhatToCheck() {
      #expect((RappPairingModel.Failure.unreachable.message) == (Self.unreachableMessage))
    }

    @Test
    internal func testOnlyNetworkFailuresOfferTheSettings() {
      #expect((RappPairingModel.Failure.localNetworkDenied.opensNetworkSettings))
      #expect((RappPairingModel.Failure.unreachable.opensNetworkSettings))
      #expect(!(RappPairingModel.Failure.reported(Self.notAccepted).opensNetworkSettings))
    }

    @Test
    internal func testALocalCloseShowsNothing() {
      #expect((RappPairingModel.failure(for: Reason.localRequest)) == nil)
    }

    @Test
    internal func testAFailureAfterTheCodeWasTakenEndsThePairing() {
      #expect(
        (RappPairingModel.failure(for: Reason.ceremonyEnded(.attemptTimedOut))?.message)
          == (String(localized: "Pairing ended before it was completed.")))
    }

    @Test
    internal func testNoneFoundIsSaidInEveryLanguage() throws {
      try Self.assertTranslations(
        of: "No phone in pairing mode was found.",
        finnish: "Yhdistämistilassa olevaa puhelinta ei löytynyt.",
        swedish: "Ingen telefon i parkopplingsläge hittades.")
    }

    @Test
    internal func testLocalNetworkDenialIsSaidInEveryLanguage() throws {
      try Self.assertTranslations(
        of: """
          macOS is blocking RefineID from the local network. Allow it in \
          System Settings › Privacy & Security › Local Network.
          """,
        finnish: """
          macOS estää RefineIDtä käyttämästä lähiverkkoa. Salli se kohdassa \
          Järjestelmäasetukset › Tietosuoja ja suojaus › Lähiverkko.
          """,
        swedish: """
          macOS hindrar RefineID från att använda det lokala nätverket. Tillåt det i \
          Systeminställningar › Integritet och säkerhet › Lokalt nätverk.
          """)
    }
  }
#endif
