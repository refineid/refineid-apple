// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD

  import CardCore
  import RappEngine

  /// PIN 1 the holder entered on this phone, bound to the certificate
  /// fingerprint of the card that accepted it while ``Pin1Retention``
  /// permits holding (RAPP v26.11.8 section 8.4 item 1, section 11 item 2).
  ///
  /// Held only in this process's memory, never in storage, so it ends with
  /// the process and with a restart. Holding starts only on an accepted
  /// login whose pre-VERIFY probe is at the five-try limit or verified, and
  /// ends on any other probe reading or failed counter read, when the card
  /// leaves the reader or the holder removes it from the phone, when another
  /// card takes its place, when the card refuses it, and when the holder
  /// forgets the card's setup. While it is held, a browser authentication
  /// runs with no prompt. The digits live only in the entry's zeroizing
  /// store.
  internal enum HeldPin1 {
    internal static let shared = CardBoundPin1<RappCertificateFingerprint>.Vault()
  }

#endif
