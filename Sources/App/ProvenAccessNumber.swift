// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD

  import CardCore

  /// An access number and the digits a secure channel proved, kept together
  /// so the record written afterwards is stored under what opened it.
  ///
  /// The number itself keeps its digits private, because a value that can
  /// be read back is a value that can be logged. Setup needs them once, to
  /// store what the card just accepted, so they travel beside it rather
  /// than being pulled out of it.
  internal struct ProvenAccessNumber {
    internal let value: CardAccessNumber
    internal let digits: String
  }

#endif
