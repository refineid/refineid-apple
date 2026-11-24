// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Estonian eID (EstEID 2025 and EstEID 2018 / 2018 v2) selection,
/// certificate discovery, and document-number reads split from `CardOperations.swift`.
extension CardOperations {
  /// Selects the EstEID 2018 IAS-ECC root application (Cosmo v8 or Cosmo X)
  /// and records `.estonian2018` in the session memo.
  public func selectEstonian2018Application() throws {
    let candidates: [ApplicationIdentifier] =
      referenceMemo.estonian2018Aid.map { [$0] } ?? [
        .estonian2018Application,
        .estonian2018V2Application,
      ]
    var lastStatus = StatusWord.fileNotFound
    for aid in candidates {
      let response = try transmit(.selectApplication(aid))
      if response.statusWord == .success {
        referenceMemo.resolved = .estonian2018
        referenceMemo.estonian2018Aid = aid
        return
      }
      lastStatus = response.statusWord
    }
    throw CardOperationError.selectRejected(lastStatus)
  }

  /// Reads both the chip-level security serial and the printed card/document
  /// number in one session.
  ///
  /// FINEID cards derive their printed serial from `EF.TokenInfo`; EstEID 2025
  /// keeps its full binary chip serial in `EF.TokenInfo` and reads its printed
  /// document number from `DF.DD / EF.5007`; EstEID 2018 reads its validated
  /// document number from `MF / EF.D003` (with `DF.5000 / EF.5007` fallback).
  public func readCardIdentitySerials() throws -> CardIdentitySerials {
    if referenceMemo.resolved == .estonian2018 {
      let documentNumber = try readEstonian2018DocumentNumber()
      return CardIdentitySerials(
        chipSerial: ChipSerial(documentNumber: documentNumber),
        printedSerial: PrintedSerial(documentNumber: documentNumber)
      )
    }
    let numbering = try resolveCredentialReferences()
    let chipSerial = try readChipSerial()
    if numbering == .estonian2025 {
      let documentNumber = try readEstonian2025DocumentNumber()
      return CardIdentitySerials(
        chipSerial: chipSerial,
        printedSerial: PrintedSerial(documentNumber: documentNumber)
      )
    }
    guard let printed = PrintedSerial(chipSerial: chipSerial) else {
      throw CardOperationError.tokenInfoMalformed
    }
    return CardIdentitySerials(chipSerial: chipSerial, printedSerial: printed)
  }

  /// Reads the plain-ASCII PD7 document number from `DF.DD / EF.5007` inside
  /// the EstEID 2025 eID application and leaves the eID application selected.
  public func readEstonian2025DocumentNumber() throws -> DocumentNumber {
    try selectCardApplication()
    try selectPath([.estonianDocumentDataDirectory, .estonianDocumentNumberPlain])
    var assembler = BinaryReadAssembler(
      mode: .toEndOfFile,
      expectedLength: DocumentNumber.probeReadCap,
      chunkLength: channel.readChunkLength
    )
    let raw = try drive(&assembler)
    try selectCardApplication()
    guard let documentNumber = DocumentNumber(asciiBytes: raw) else {
      throw CardOperationError.tokenInfoMalformed
    }
    return documentNumber
  }

  /// Reads the EstEID 2018 document number from `MF / EF.D003` (DER TLV),
  /// falling back to plain-ASCII `MF / DF.5000 / EF.5007`.
  public func readEstonian2018DocumentNumber() throws -> DocumentNumber {
    do {
      try selectEstonian2018Root()
      let tlv = try readSelectedFile(.estonianDocumentNumberTlv)
      if let parsed = DocumentNumber(tlvBytes: tlv) {
        return parsed
      }
    } catch let error as CardOperationError {
      if CardOperationError.requiresCanPace(error) {
        throw error
      }
      switch error {
      case .sessionUnavailable, .exchangeUnanswered:
        throw error

      default:
        break
      }
    }
    try selectEstonian2018Root()
    try selectChildDirectory(.estonianLegacyPersonalDataDirectory)
    let raw = try readElementaryFile(
      .estonianDocumentNumberPlain,
      expectedLength: DocumentNumber.probeReadCap
    )
    guard let parsed = DocumentNumber(asciiBytes: raw) else {
      throw CardOperationError.tokenInfoMalformed
    }
    return parsed
  }

  /// Selects the EstEID 2018 root main file (`00 A4 00 0C`), falling back
  /// to explicit `3F00` and IAS-ECC AID selection.
  internal func selectEstonian2018Root() throws {
    let noData = try transmit(.selectMainFileNoData())
    if noData.statusWord == .success {
      return
    }
    let byFid = try transmit(
      .selectFile(.mainFile, selectionP1: Iso7816Values.selectByFileIdP1)
    )
    if byFid.statusWord == .success {
      return
    }
    try selectEstonian2018Application()
  }

  /// Selects a child directory (`00 A4 01 0C 02 <DF>`) under the current DF.
  internal func selectChildDirectory(_ directory: FileIdentifier) throws {
    let response = try transmit(
      .selectFile(directory, selectionP1: Iso7816Values.selectChildDfP1)
    )
    guard response.statusWord == .success else {
      throw CardOperationError.selectRejected(response.statusWord)
    }
  }

  /// Discovers EstEID 2025 certificate paths, key references, and EF.AOD from
  /// `EF.OD` (`5031`), memoizing the result for this session once `EF.OD` reads.
  internal func discoverEstonian2025Directory() {
    guard !referenceMemo.attemptedDirectoryDiscovery else { return }
    guard
      let odfData = try? readElementaryFile(.objectDirectory, expectedLength: nil)
    else {
      return
    }
    referenceMemo.attemptedDirectoryDiscovery = true
    let locations = Pkcs15Directory.locations(fromObjectDirectory: odfData)
    referenceMemo.discoveredAodFile = locations.authObjects
    let certificates: [Pkcs15Directory.Certificate]
    if let certFile = locations.certificates,
      let certData = try? readElementaryFile(certFile, expectedLength: nil)
    {
      certificates = Pkcs15Directory.certificates(fromDirectory: certData)
    } else {
      certificates = []
    }
    let keys: [Pkcs15Directory.PrivateKey]
    if let keyFile = locations.privateKeys,
      let keyData = try? readElementaryFile(keyFile, expectedLength: nil)
    {
      keys = Pkcs15Directory.privateKeys(fromDirectory: keyData)
    } else {
      keys = []
    }
    let paired = Pkcs15Inventory.pair(certificates: certificates, keys: keys)
    recordDiscoveredEntries(paired, keys: keys)
  }

  /// Reads an EstEID 2025 certificate via its discovered PKCS#15 path, falling
  /// back to the documented default `ADF1:3411` / `ADF2:3421` paths, and
  /// restores the eID application directory before returning.
  internal func readEstonian2025Certificate(_ slot: CertificateSlot) throws -> Data {
    try selectCardApplication()
    discoverEstonian2025Directory()
    let defaultPath: [FileIdentifier] =
      slot == .authentication
      ? [.estonianAwpDirectory, .estonian2025AuthCertificate]
      : [.estonianQscdDirectory, .estonian2025SignatureCertificate]
    let path = referenceMemo.discoveredCertificatePaths[slot] ?? defaultPath
    let certificate = try readSingleDerObject(atPath: path)
    try selectCardApplication()
    return certificate
  }

  /// Reads an EstEID 2018 certificate from `MF / ADF1 / 3401(3402)` or
  /// `MF / ADF2 / 341F(341E)`.
  internal func readEstonian2018Certificate(_ slot: CertificateSlot) throws -> Data {
    let candidates: [(directory: FileIdentifier, file: FileIdentifier)]
    switch slot {
    case .authentication:
      candidates = [
        (.estonianAwpDirectory, .estonian2018AuthCertificate),
        (.estonianAwpDirectory, .estonian2018SecondAuthCertificate),
      ]

    case .qualifiedSignature:
      candidates = [
        (.estonianQscdDirectory, .estonian2018SignatureCertificate),
        (.estonianQscdDirectory, .estonian2018SecondSignatureCertificate),
      ]

    case .issuing, .root, .secondAuthentication, .secondQualifiedSignature:
      throw CardOperationError.selectRejected(.fileNotFound)
    }
    var lastStatus = StatusWord.fileNotFound
    var lastReadFailure: BinaryReadFailure?
    for candidate in candidates {
      do {
        try selectEstonian2018Root()
        try selectChildDirectory(candidate.directory)
        return try readSelectedFile(candidate.file)
      } catch CardOperationError.selectRejected(let status) {
        lastStatus = status
      } catch CardOperationError.readFailed(let failure) {
        lastReadFailure = failure
      }
    }
    if let lastReadFailure {
      throw CardOperationError.readFailed(lastReadFailure)
    }
    throw CardOperationError.selectRejected(lastStatus)
  }

  /// Selects `path` inside the currently active eID application, trying
  /// path-from-MF (`00 A4 08 0C`) first and stepping DF-by-DF as fallback.
  internal func selectPath(_ path: [FileIdentifier]) throws {
    guard
      let file = path.last,
      path.count <= Pkcs15Directory.maximumPathDepth
    else {
      throw CardOperationError.selectRejected(.fileNotFound)
    }
    if path.count == 1 {
      try selectFirstThatSucceeds([
        .selectElementaryFile(file),
        .selectFile(file, selectionP1: Iso7816Values.selectByFileIdP1),
      ])
      return
    }
    if let byPathCommand = CommandApdu.selectByPath(path) {
      let byPath = try transmit(byPathCommand)
      if byPath.statusWord == .success {
        return
      }
    }
    for directory in path.dropLast() {
      try selectChildDirectory(directory)
    }
    try selectFirstThatSucceeds([
      .selectElementaryFile(file),
      .selectFile(file, selectionP1: Iso7816Values.selectByFileIdP1),
    ])
  }

  private func recordDiscoveredEntries(
    _ entries: [Pkcs15Inventory.Entry],
    keys: [Pkcs15Directory.PrivateKey]
  ) {
    for entry in entries {
      if let key = entry.key {
        if key.usage.contains(.nonRepudiation) {
          referenceMemo.discoveredCertificatePaths[.qualifiedSignature] = entry.certificate.path
          if let ref = key.keyReference {
            referenceMemo.discoveredKeyReferences[.qualifiedSignature] = ref
          }
        } else if key.usage.contains(.sign) {
          referenceMemo.discoveredCertificatePaths[.authentication] = entry.certificate.path
          if let ref = key.keyReference {
            referenceMemo.discoveredKeyReferences[.authentication] = ref
          }
        }
      }
    }
    for key in keys {
      if key.usage.contains(.nonRepudiation),
        referenceMemo.discoveredKeyReferences[.qualifiedSignature] == nil,
        let ref = key.keyReference
      {
        referenceMemo.discoveredKeyReferences[.qualifiedSignature] = ref
      } else if key.usage.contains(.sign),
        referenceMemo.discoveredKeyReferences[.authentication] == nil,
        let ref = key.keyReference
      {
        referenceMemo.discoveredKeyReferences[.authentication] = ref
      }
    }
  }

  /// Selects a multi-segment path inside the active eID application and reads
  /// one DER object.
  private func readSingleDerObject(atPath path: [FileIdentifier]) throws -> Data {
    try selectPath(path)
    var assembler = BinaryReadAssembler(
      mode: .singleDerObject,
      chunkLength: channel.readChunkLength
    )
    return try drive(&assembler)
  }
}
