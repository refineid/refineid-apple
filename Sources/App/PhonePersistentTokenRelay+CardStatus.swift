// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation

  /// The custodian's word on its card (RAPP v26.10.18 §8.4).
  @MainActor
  extension PhonePersistentTokenRelay {
    /// Tells the connected requester whether a card can be served (RAPP
    /// v26.10.18 §8.4); nothing is sent without a session.
    internal func reportCardStatus() {
      guard let coordinator else { return }
      let present = cardReport.present
      Task { try? await coordinator.reportCardStatus(present: present) }
    }

    /// A reader card or a prime arrived or left; a card that can be
    /// served again was coupled or primed by the holder.
    internal func cardAvailabilityChanged(servable: Bool) {
      apply(cardReport.availabilityChanged(servable: servable))
    }

    /// Sends `word` when a transition produced one.
    internal func apply(_ word: CustodianCardReport.Word?) {
      guard word != nil else { return }
      reportCardStatus()
    }
  }
#endif
