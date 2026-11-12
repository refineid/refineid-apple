// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD
  import CardCore

  extension CardPriming {
    /// Personal setup lets the card finish PACE before replacing the field.
    ///
    /// The ordinary short response budget can interrupt a delayed exchange
    /// while the system still owns a usable NFC field.
    internal static func responseWait(
      for kind: ContactlessCardKind,
      isRecovery: Bool
    ) -> SmartCardChannel.ResponseWait {
      kind == .personal || isRecovery ? .nearFieldRecovery : .nearField
    }
  }
#endif
