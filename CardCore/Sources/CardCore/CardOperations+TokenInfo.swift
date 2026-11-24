// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Token-info and credential-attribute read helpers split from `CardOperations.swift`.
extension CardOperations {
  /// Reads one credential's usage allowances, counter-safe.
  ///
  /// The same GET DATA container the retry probe uses, read for the
  /// other numbers in it: whether the card limits how many times this
  /// credential may be used, and - for the PUK - how many unblocks it
  /// has left.
  public func readAllowances(role: CredentialRole) throws -> CredentialAllowances? {
    let references = (try? resolveCredentialReferences()) ?? .citizen
    guard references != .estonian2018 else { return nil }
    let response = try transmit(.readCredentialAttributes(role: role, references: references))
    guard response.statusWord == .success else { return nil }
    return CredentialAttributes.allowances(fromResponseBody: response.payload)
  }

  /// Reads a PIN's changed-since-manufacture record, counter-safe
  /// (the GET DATA PIN-container form, S1 v4.2 section 3.15.3; GED24035
  /// section 8.3.4).
  ///
  /// The record decides whether a PIN awaits activation under both
  /// S4-1 section 4.6 schemes. Any refusal answers `unreadable` rather than
  /// throwing: no decision may turn an unreadable record into permission.
  public func readPinChangeRecord(role: CredentialRole) throws -> PinChangeRecord {
    let references = referenceMemo.resolved ?? .citizen
    guard references != .estonian2018 else { return .unreadable }
    let response = try transmit(.readCredentialAttributes(role: role, references: references))
    guard response.statusWord == .success else {
      return .unreadable
    }
    return CredentialAttributes.pinChangeRecord(fromResponseBody: response.payload)
  }

  /// What `EF.TokenInfo` says the card is, for the status screen.
  ///
  /// Best effort by nature: the fields are optional in PKCS#15, so a
  /// card that says nothing about itself is normal and answers nil.
  public func readTokenDescription() throws -> String? {
    if referenceMemo.resolved == .estonian2018 {
      return "Estonian eID"
    }
    let selected = try transmit(.selectElementaryFile(.tokenInfo))
    guard selected.statusWord == .success else {
      throw CardOperationError.selectRejected(selected.statusWord)
    }
    var assembler = BinaryReadAssembler(
      mode: .singleDerObject,
      chunkLength: channel.readChunkLength
    )
    return TokenInfoFile.description(fromContent: try drive(&assembler))
  }

  /// Reads the card's full hardware serial for card-bound security bindings.
  ///
  /// FINEID and EstEID 2025 supply it from `EF.TokenInfo` (`5032`); EstEID 2018
  /// has no serialNumber in CIAInfo and uses its validated `EF.D003` document
  /// number instead.
  public func readChipSerial() throws -> ChipSerial {
    if referenceMemo.resolved == .estonian2018 {
      let documentNumber = try readEstonian2018DocumentNumber()
      return ChipSerial(documentNumber: documentNumber)
    }
    do {
      return try readTokenInfoChipSerial()
    } catch CardOperationError.selectRejected(.fileNotFound)
      where referenceMemo.resolved == .estonian2025
    {
      try selectCardApplication()
      return try readTokenInfoChipSerial()
    }
  }

  private func readTokenInfoChipSerial() throws -> ChipSerial {
    let selected = try transmit(.selectElementaryFile(.tokenInfo))
    guard selected.statusWord == .success else {
      throw CardOperationError.selectRejected(selected.statusWord)
    }
    var assembler = BinaryReadAssembler(
      mode: .singleDerObject,
      chunkLength: channel.readChunkLength
    )
    let content = try drive(&assembler)
    guard let serial = TokenInfoFile.serial(fromContent: content) else {
      throw CardOperationError.tokenInfoMalformed
    }
    return serial
  }
}
