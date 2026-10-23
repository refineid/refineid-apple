// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

/// The no-card instructions say the same thing in every language: with
/// remote use off the window asks for a reader, or for the card in it; with
/// remote use on and no phone paired it asks for the phone's code.
@Suite
internal struct ReaderInstructionStringsTests {
  /// The remote-use switch's name and states in Finnish, by key.
  private static let remoteUseFinnish: [String: String] = [
    "Remote Access": "Etäkäyttö",
    "Off": "Pois",
    "On": "Päällä",
    "Phone connected": "Puhelin yhdistetty",
    "Blocked: %@": "Estetty: %@",
    "Bluetooth is off": "Bluetooth on pois päältä",
    "Bluetooth is not allowed": "Bluetoothia ei ole sallittu",
    "local network is not allowed": "paikallisverkkoa ei ole sallittu",
  ]

  /// The same in Swedish.
  private static let remoteUseSwedish: [String: String] = [
    "Remote Access": "Fjärråtkomst",
    "Off": "Av",
    "On": "På",
    "Phone connected": "Telefon ansluten",
    "Blocked: %@": "Blockerad: %@",
    "Bluetooth is off": "Bluetooth är avstängt",
    "Bluetooth is not allowed": "Bluetooth är inte tillåtet",
    "local network is not allowed": "lokalt nätverk är inte tillåtet",
  ]

  private static var root: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private static func catalog() throws -> [String: Any] {
    let url = root.appending(path: "Sources/App/Localizable.xcstrings")
    let data = try Data(contentsOf: url)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["sourceLanguage"] as? String == "en")
    return try #require(json["strings"] as? [String: Any])
  }

  private static func value(
    for key: String, language: String, in strings: [String: Any]
  ) throws -> String {
    let entry = try #require(strings[key] as? [String: Any])
    let localizations = try #require(entry["localizations"] as? [String: Any])
    let localization = try #require(localizations[language] as? [String: Any])
    let unit = try #require(localization["stringUnit"] as? [String: Any])
    return try #require(unit["value"] as? String)
  }

  @Test
  internal func readerWithoutCardInstructionMatchesInEveryLanguage() throws {
    let strings = try Self.catalog()
    #expect(
      try Self.value(
        for: "Insert the card into the reader.", language: "fi", in: strings
      ) == "Syötä kortti lukijaan."
    )
    #expect(
      try Self.value(
        for: "Insert the card into the reader.", language: "sv", in: strings
      ) == "Sätt in kortet i läsaren."
    )
  }

  @Test
  internal func phoneReaderInstructionMatchesInEveryLanguage() throws {
    let strings = try Self.catalog()
    let key = "Open RefineID remote access on your phone and enter the pairing code:"
    #expect(
      try Self.value(for: key, language: "fi", in: strings)
        == "Avaa puhelimesta RefineID etäkäyttö ja syötä yhdistämiskoodi:"
    )
    #expect(
      try Self.value(for: key, language: "sv", in: strings)
        == "Öppna RefineID fjärråtkomst på telefonen och ange kopplingskoden:"
    )
  }

  @Test
  internal func pairedPhoneAndPinCodesMatchInEveryLanguage() throws {
    let strings = try Self.catalog()
    let finnish: [String: String] = [
      "(paired phone: %@)": "(yhdistetty puhelin: %@)",
      "Paired phone: %@": "Yhdistetty puhelin: %@",
      "Remove phone pairing": "Poista puhelimen yhdistäminen",
      "PIN Codes": "PIN-koodit",
    ]
    let swedish: [String: String] = [
      "(paired phone: %@)": "(kopplad telefon: %@)",
      "Paired phone: %@": "Kopplad telefon: %@",
      "Remove phone pairing": "Ta bort kopplingen till telefonen",
      "PIN Codes": "PIN-koder",
    ]
    for (key, value) in finnish {
      #expect(try Self.value(for: key, language: "fi", in: strings) == value)
    }
    for (key, value) in swedish {
      #expect(try Self.value(for: key, language: "sv", in: strings) == value)
    }
  }

  @Test
  internal func readerRequestWithRemoteUseOffMatchesInEveryLanguage() throws {
    let strings = try Self.catalog()
    let key = "Connect a card reader."
    #expect(try Self.value(for: key, language: "fi", in: strings) == "Liitä kortinlukija.")
    #expect(try Self.value(for: key, language: "sv", in: strings) == "Anslut en kortläsare.")
  }

  @Test
  internal func remoteUseSwitchWordsMatchInEveryLanguage() throws {
    let strings = try Self.catalog()
    for (key, value) in Self.remoteUseFinnish {
      #expect(try Self.value(for: key, language: "fi", in: strings) == value)
    }
    for (key, value) in Self.remoteUseSwedish {
      #expect(try Self.value(for: key, language: "sv", in: strings) == value)
    }
  }

  @Test
  internal func phoneCardRequestsMatchInEveryLanguage() throws {
    let strings = try Self.catalog()
    let reader = "Insert the card into the phone's card reader."
    let phone = "Place the card on the phone."
    #expect(
      try Self.value(for: reader, language: "fi", in: strings)
        == "Syötä kortti puhelimen kortinlukijaan.")
    #expect(
      try Self.value(for: reader, language: "sv", in: strings)
        == "Sätt in kortet i telefonens kortläsare.")
    #expect(try Self.value(for: phone, language: "fi", in: strings) == "Aseta kortti puhelimeen.")
    #expect(try Self.value(for: phone, language: "sv", in: strings) == "Lägg kortet på telefonen.")
  }

  @Test
  internal func viewsUseTheTranslatedKeys() throws {
    let identity = try String(
      contentsOf: Self.root.appending(path: "Sources/App/IdentityStateView.swift"),
      encoding: .utf8
    )
    #expect(identity.contains("Insert the card into the reader."))
    let prompt = try String(
      contentsOf: Self.root.appending(path: "Sources/App/RemotePairingPromptView.swift"),
      encoding: .utf8
    )
    #expect(
      prompt.contains("Open RefineID remote access on your phone and enter the pairing code:")
    )
    let notes = try String(
      contentsOf: Self.root.appending(path: "Sources/App/StatusView+Notes.swift"),
      encoding: .utf8
    )
    #expect(notes.contains("RemoteUseSwitch.shared.isOn"))
    #expect(!notes.contains("isReaderConnected"))
    #expect(identity.contains("Connect a card reader."))
    let remoteUseFiles = try ["RemoteUseState.swift", "RemoteUseBlockage.swift"].map { name in
      try String(contentsOf: Self.root.appending(path: "Sources/App/\(name)"), encoding: .utf8)
    }
    let remoteUse = remoteUseFiles.joined()
    for key in Self.remoteUseFinnish.keys {
      #expect(remoteUse.contains(key.replacingOccurrences(of: "%@", with: "\\(")))
    }
    let phoneLine = try String(
      contentsOf: Self.root.appending(path: "Sources/App/PairedPhoneLine.swift"),
      encoding: .utf8
    )
    #expect(phoneLine.contains("(paired phone: \\(phone))"))
    #expect(phoneLine.contains("Paired phone: \\(phone)"))
    #expect(phoneLine.contains("Remove phone pairing"))
    let pinCodes = try String(
      contentsOf: Self.root.appending(path: "Sources/App/PinCodesButton.swift"),
      encoding: .utf8
    )
    #expect(pinCodes.contains("PIN Codes"))
    let request = try String(
      contentsOf: Self.root.appending(path: "Sources/App/PhoneCardRequestLine.swift"),
      encoding: .utf8
    )
    #expect(request.contains("Insert the card into the phone's card reader."))
    #expect(request.contains("Place the card on the phone."))
  }
}
