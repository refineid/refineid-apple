// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD

  import CardCore
  import RappEngine

  /// PIN 1 the holder entered on this phone, bound to the certificate
  /// fingerprint of the card it was entered for (RAPP v26.10.29 §8.4 item
  /// 1, §11 item 2).
  ///
  /// Held only in this process's memory, never in storage, so it ends with
  /// the process and with a restart. It also ends when the card leaves the
  /// reader or the holder removes it from the phone, when another card
  /// takes its place, when the card refuses it, and when the holder
  /// forgets the card's setup. While it is held, a browser authentication
  /// runs with no prompt.
  @MainActor
  internal enum HeldPin1 {
    internal static var shared = CardBoundPin1<RappCertificateFingerprint>()
  }

#endif
