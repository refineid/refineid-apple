// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Reading the travel-document application a Finnish identity card
/// also implements (ICAO 9303).
///
/// Everything here needs an already-open PACE channel. The
/// application answers a SELECT on the plain channel, which is what
/// makes it useful for discovery, but every file inside is refused
/// until secure messaging is running - so these operations are given
/// a `CardOperations` built over the secure-messaged transport, and
/// they read files rather than proving anything about the card.
///
/// No PIN is presented on this path, so no retry counter is touched.
extension CardOperations {
  /// Selects the eMRTD application; its files become reachable.
  public func selectTravelDocumentApplication() throws {
    let response = try transmit(
      .selectApplication(.travelDocumentApplication)
    )
    guard response.statusWord == .success else {
      throw CardOperationError.selectRejected(response.statusWord)
    }
  }

  /// Which data groups this card carries, from EF.COM.
  ///
  /// The list is the card's own inventory, and it is read before any
  /// data group so nothing is asked for that is not there. That is
  /// not tidiness: a READ BINARY against a data group the card never
  /// provisioned desynchronises the secure-messaging counter on these
  /// cards, and every later command in the session then fails for a
  /// reason that has nothing to do with the command.
  public func readDataGroupInventory() throws -> DataGroupInventory {
    let file = IcaoTlv(try readTravelDocumentFile(.commonData))
    guard let template = file.outermost else {
      return DataGroupInventory(listing: Data())
    }
    for field in file.records(within: template.content)
    where field.tag == FineidValues.dataGroupListTag && !field.hasTwoByteTag {
      return DataGroupInventory(listing: file.content(of: field))
    }
    return DataGroupInventory(listing: Data())
  }

  /// The holder's handwritten signature, when the card carries one.
  ///
  /// Answers nil when the inventory does not list DG7, rather than
  /// asking for it and finding out the expensive way.
  public func readDisplayedSignature() throws -> DisplayedSignature.Image? {
    try readDisplayedSignature(listedBy: readDataGroupInventory())
  }

  /// DG7 under an inventory already read in this secure session.
  public func readDisplayedSignature(
    listedBy inventory: DataGroupInventory
  ) throws -> DisplayedSignature.Image? {
    guard inventory.carriesDisplayedSignature else {
      return nil
    }
    let group = try readTravelDocumentFile(.displayedSignature)
    return try DisplayedSignature.image(inDataGroup: group)
  }

  /// Selects one file under the travel-document application and
  /// reads its single DER object.
  private func readTravelDocumentFile(_ file: FileIdentifier) throws -> Data {
    let selected = try transmit(.selectElementaryFile(file))
    guard selected.statusWord == .success else {
      throw CardOperationError.selectRejected(selected.statusWord)
    }
    var assembler = BinaryReadAssembler(
      mode: .singleDerObject,
      chunkLength: channel.readChunkLength
    )
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
}
