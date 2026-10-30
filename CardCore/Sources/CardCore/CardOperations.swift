// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The read-only card operations of the minimal driver, written against
/// `CardChannel` so every flow is testable without hardware.
///
/// One value serves one exclusive card session. Every operation here is
/// idempotent and credential-free; PIN-bearing flows are a separate,
/// noncopyable path.
public struct CardOperations {
  /// Upper bound on GET RESPONSE continuations for one command; a card
  /// announcing more is misbehaving.
  private static let maximumContinuations = 128

  /// Internal, not private: the credential-bearing extension in
  /// CardOperations+Credentials.swift drives the same session.
  internal let channel: any CardChannel

  /// Which credential reference numbering this session's card uses.
  ///
  /// Filled by the first resolution and read by everything after it.
  /// Internal, not private: the credential and signing extensions read
  /// and feed the same memory.
  internal let referenceMemo = CredentialReferenceMemo()

  /// Wraps one exclusive session's transport.
  public init(channel: any CardChannel) {
    self.channel = channel
  }

  /// Selects the FINEID eID application; the card's DF becomes current.
  ///
  /// Success is also the "supported card" signal: an absent application
  /// answers `fileNotFound`.
  public func selectFineidApplication() throws {
    let response = try transmit(
      .selectApplication(.fineidApplication)
    )
    guard response.statusWord == .success else {
      throw CardOperationError.selectRejected(response.statusWord)
    }
  }

  /// Selects and reads one EF under the current DF to its end.
  public func readElementaryFile(
    _ file: FileIdentifier,
    expectedLength: Int?
  ) throws -> Data {
    let selected = try transmit(.selectElementaryFile(file))
    guard selected.statusWord == .success else {
      throw CardOperationError.selectRejected(selected.statusWord)
    }
    var assembler = BinaryReadAssembler(
      mode: .toEndOfFile,
      expectedLength: expectedLength,
      chunkLength: channel.readChunkLength
    )
    return try drive(&assembler)
  }

  /// Reads what the card's PKCS#15 directories say it carries.
  ///
  /// The application must already be selected. Each certificate is
  /// paired with the key sharing its identifier, which is where the
  /// key reference comes from; a certificate with no key is an
  /// authority certificate the card files alongside the leaves.
  public func readPkcs15Inventory() throws -> [Pkcs15Inventory.Entry] {
    let directory = try readDirectoryFile(.objectDirectory)
    let locations = Pkcs15Directory.locations(fromObjectDirectory: directory)
    let certificates = try locations.certificates.map { file in
      Pkcs15Directory.certificates(fromDirectory: try readDirectoryFile(file))
    }
    let keys = try locations.privateKeys.map { file in
      Pkcs15Directory.privateKeys(fromDirectory: try readDirectoryFile(file))
    }
    return Pkcs15Inventory.pair(certificates: certificates ?? [], keys: keys ?? [])
  }

  /// Reads one directory file from wherever the card keeps it.
  ///
  /// The application directory reached by name is one home; the
  /// signature directory is the other, which is where the certificate
  /// leaves live on the cards that file them there. A directory read
  /// after a certificate read cannot assume which is current, so each
  /// attempt navigates first.
  private func readDirectoryFile(_ file: FileIdentifier) throws -> Data {
    var lastFailure: (any Error)?
    for directory in [CertificateDirectory.pkcs15Application, .esignApplication] {
      do {
        try navigate(to: directory)
        return try readElementaryFile(file, expectedLength: nil)
      } catch {
        lastFailure = error
      }
    }
    throw lastFailure ?? CardOperationError.readFailed(.emptyFile)
  }

  /// Reads one certificate's DER bytes from its slot.
  ///
  /// Tries each of the slot's documented locations in order: navigates
  /// to its directory, selects the certificate EF, and reads it to the
  /// end. A refused SELECT moves on to the next location - that answer
  /// is what distinguishes the citizen layout from the organization
  /// one - and so does a refused read: the organization card answers
  /// success to a select-by-identifier of a file it does not have,
  /// then refuses READ BINARY with no current file, which is the same
  /// "not here" answer wearing a select that lied. Returns the raw
  /// DER: CardCore never parses X.509 - the platform does
  /// (`SecCertificateCreateWithData`). A slot absent everywhere
  /// answers its last failure, so callers can treat it as "not
  /// provisioned".
  public func readCertificate(_ slot: CertificateSlot) throws -> Data {
    var lastRejection = StatusWord.other(0)
    var lastReadFailure: BinaryReadFailure?
    for location in slot.locations {
      do {
        try navigate(to: location.directory)
        return try readSelectedFile(location.file)
      } catch CardOperationError.selectRejected(let status) {
        lastRejection = status
      } catch CardOperationError.readFailed(let failure) {
        lastReadFailure = failure
      }
    }
    if let lastReadFailure {
      throw CardOperationError.readFailed(lastReadFailure)
    }
    throw CardOperationError.selectRejected(lastRejection)
  }

  /// Makes the organization card's signature directory current.
  ///
  /// The card's qualified-signature service lives in DF.ESIGN
  /// (FINEID S4-2 v4.0 §4.6.21): its certificate is filed there, and
  /// the signature ceremony runs there. Public so a qualified sign
  /// can enter the directory before verifying PIN2; the citizen card
  /// has no such directory and never needs this.
  public func selectEsignDirectory() throws {
    try navigate(to: .esignApplication)
  }

  /// Makes a certificate location's directory current.
  private func navigate(to directory: CertificateDirectory) throws {
    switch directory {
    case .pkcs15Application:
      try selectFineidApplication()

    case .mainFile:
      try selectMainFile()

    case .esignApplication:
      // By name first: the file-identifier variant can answer
      // success without making the directory current, after which
      // the certificate select misses and the read fails on a card
      // that serves the same bytes happily under the named
      // directory. The name is the S4-2 v4.0 §4.6.21 selector; the
      // file-identifier form stays as the fallback for cards that
      // refuse selection by name.
      try selectMainFile()
      try selectFirstThatSucceeds([
        .selectApplication(.esignDirectory),
        .selectFile(.esignDirectory, selectionP1: Iso7816Values.selectByFileIdP1),
      ])
    }
  }

  /// Reads and parses EF.CardAccess: what PACE variants and domain
  /// parameters this card advertises.
  ///
  /// Runs on the plain channel from the main file, before any secure
  /// channel exists -- the file is readable unauthenticated because a
  /// terminal needs it to know how to open one. Nothing in the login
  /// path calls this; it answers whether a cheaper suite than the fixed
  /// one is on offer.
  ///
  /// Empty when the file carries nothing this build can read, which is
  /// not a card failure: a card is free to advertise protocols nobody
  /// here parses, and the fixed suite is what runs either way. An
  /// absent file throws at selection, like any other missing EF.
  public func readCardAccessInfo() throws -> [CardAccessFile.SecurityInfo] {
    try selectMainFile()
    return CardAccessFile.parse(try readSelectedFile(.cardAccess))
  }

  /// Selects the main file, trying the proven wire variants in order
  /// (select-by-file-id, then select-by-name) since card generations
  /// differ.
  ///
  /// Public because PACE runs from the main file and nothing else can
  /// put the card there. A contactless card is discovered by selecting
  /// the eMRTD application, and MSE:Set AT from an applet context is
  /// answered `6985`, so the contactless caller makes the main file
  /// current before the first PACE command.
  public func selectMainFile() throws {
    try selectFirstThatSucceeds([
      .selectFile(.mainFile, selectionP1: Iso7816Values.selectByFileIdP1),
      .selectFile(.mainFile, selectionP1: Iso7816Values.selectByAidP1),
    ])
  }

  /// Selects the EF then reads exactly its single DER object.
  ///
  /// The certificate slots hold one DER object. Reading to the
  /// DER-declared length (not the padded file end) is required: the
  /// card refuses a READ BINARY that overruns the file, so a whole-file
  /// read truncates the certificate.
  private func readSelectedFile(_ file: FileIdentifier) throws -> Data {
    try selectFirstThatSucceeds([
      .selectElementaryFile(file),
      .selectFile(file, selectionP1: Iso7816Values.selectByFileIdP1),
    ])
    var assembler = BinaryReadAssembler(
      mode: .singleDerObject,
      chunkLength: channel.readChunkLength
    )
    return try drive(&assembler)
  }

  /// Drives an assembler to completion over the transport.
  private func drive(_ assembler: inout BinaryReadAssembler) throws -> Data {
    while case .transmit(let command) = assembler.nextStep {
      assembler.accept(try transmit(command))
    }
    switch assembler.nextStep {
    case .complete(let content):
      return content

    case .failed(let failure):
      throw CardOperationError.readFailed(failure)

    case .transmit:
      throw CardOperationError.malformedResponse
    }
  }

  /// Transmits each command until one answers success; throws
  /// `selectRejected` with the last status if none do.
  private func selectFirstThatSucceeds(_ commands: [CommandApdu]) throws {
    var lastStatus = StatusWord.other(0)
    for command in commands {
      let response = try transmit(command)
      if response.statusWord == .success {
        return
      }
      lastStatus = response.statusWord
    }
    throw CardOperationError.selectRejected(lastStatus)
  }

  /// Reads one credential's usage allowances, counter-safe.
  ///
  /// The same GET DATA container the retry probe uses, read for the
  /// other numbers in it: whether the card limits how many times this
  /// credential may be used, and - for the PUK - how many unblocks it
  /// has left.
  public func readAllowances(role: CredentialRole) throws -> CredentialAllowances? {
    let response = try transmit(.readCredentialAttributes(role: role))
    guard response.statusWord == .success else { return nil }
    return CredentialAttributes.allowances(fromResponseBody: response.payload)
  }

  /// Reads a PIN's changed-since-manufacture record, counter-safe
  /// (the GET DATA PIN-container form, S1 v4.2 §3.15.3).
  ///
  /// The record is the activation signal for a card issued from
  /// 13 January 2026. Any refusal answers `unreadable` rather than
  /// throwing: the record is advisory, and no decision may turn an
  /// unreadable record into permission.
  public func readPinChangeRecord(role: CredentialRole) throws -> PinChangeRecord {
    let response = try transmit(.readCredentialAttributes(role: role))
    guard response.statusWord == .success else {
      return .unreadable
    }
    return CredentialAttributes.pinChangeRecord(fromResponseBody: response.payload)
  }

  /// Reads the full hardware serial from EF.TokenInfo.
  ///
  /// Reads the single DER object (the PKCS#15 TokenInfo SEQUENCE), not to
  /// the padded file end: a whole-file read pulls trailing padding that
  /// the card either refuses (overrun) or that defeats the DER parse -
  /// exactly the failure the certificate reads already avoid.
  /// What EF.TokenInfo says the card is, for the status screen.
  ///
  /// Best effort by nature: the fields are optional in PKCS#15, so a
  /// card that says nothing about itself is normal and answers nil.
  public func readTokenDescription() throws -> String? {
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

  /// Reads the card's full hardware serial from EF.TokenInfo.
  ///
  /// The serial is what a cached PIN is bound to, so it is read fresh in
  /// the same session that will spend the PIN.
  public func readChipSerial() throws -> ChipSerial {
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

  /// Sends one idempotent command and runs the T=0 `61xx` GET RESPONSE
  /// continuation to completion, bounded in rounds and total size.
  ///
  /// Automatic continuation is safe here precisely because only the
  /// idempotent command class reaches this path; the credential-bearing
  /// path is a separate type and never continues automatically
  /// (Documentation/release-plan.md section 4.3). Internal, not
  /// private: the signing extension in CardOperations+Signing.swift
  /// drives the same session.
  internal func transmit(_ command: CommandApdu) throws -> ResponseApdu {
    var response = try transmitOnce(command.encoded)
    var joined = response.payload
    var rounds = 0
    while case .responseAvailable(let count) = response.statusWord {
      rounds += 1
      guard
        rounds <= Self.maximumContinuations,
        joined.count <= BinaryReadAssembler.maximumTotalLength
      else {
        throw CardOperationError.malformedResponse
      }
      response = try transmitOnce(
        CommandApdu.getResponse(announcedCount: count).encoded
      )
      joined.append(response.payload)
    }
    return ResponseApdu(payload: joined, statusWord: response.statusWord)
  }

  private func transmitOnce(_ payload: Data) throws -> ResponseApdu {
    let raw = try channel.transmit(payload)
    guard let response = ResponseApdu(raw: raw) else {
      throw CardOperationError.malformedResponse
    }
    return response
  }
}
