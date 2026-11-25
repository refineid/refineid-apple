// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation

  /// Read-only card facts gathered before showing or updating a Web eID prompt.
  internal struct WebEidCardPreview: Equatable, Sendable {
    internal let holderName: String
    internal let certificateDER: Data
    internal let chipSerial: ChipSerial
    internal let profile: CardKeyProfile
    internal let pinLengths: CardPinLengths
    internal let pin2RequiresChangeBeforeSigning: Bool
    internal let retryProbe: RetryProbeOutcome?
    internal let retryFloorVerdict: RetryFloorVerdict
    internal let certificateMatchesExpected: Bool
  }

#endif
