// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension CardOperations {
  /// Selects the main file, trying the proven wire variants in order
  /// (select-by-file-id, then select-by-name) since card generations
  /// differ.
  ///
  /// Public because PACE runs from the main file and nothing else can
  /// put the card there. A contactless card is discovered by selecting
  /// the eMRTD application, and MSE:Set AT from an applet context is
  /// answered `6985`, so the contactless caller makes the main file
  /// current before the first PACE command.
  ///
  /// An organization card on the contactless interface answers `6985` to
  /// the select by file identifier before PACE, and answers the select by
  /// name with no usable response, after which the phone's platform ends
  /// the card session (observed on hardware). That refusal is therefore
  /// final: the card is left where it is, from where EF.CardAccess is
  /// still selected and read.
  public func selectMainFile() throws {
    let byFileId = try transmit(
      .selectFile(.mainFile, selectionP1: Iso7816Values.selectByFileIdP1))
    if byFileId.statusWord == .success {
      return
    }
    guard byFileId.statusWord != .conditionsNotSatisfied else {
      throw CardOperationError.selectRejected(byFileId.statusWord)
    }
    try selectFirstThatSucceeds([
      .selectFile(.mainFile, selectionP1: Iso7816Values.selectByAidP1)
    ])
  }
}
