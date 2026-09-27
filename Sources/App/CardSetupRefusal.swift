// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import CardCore

  /// What a setup hold learned from the card that the next screen routes on.
  ///
  /// The hold reads the card once, so anything a later decision needs has to
  /// leave that hold with it. Kept outside the priming flow because the model
  /// that carries it serves systems older than the card slot the flow needs.
  internal enum CardSetupRefusal: Equatable, Sendable {
    /// The card has not been given its first holder codes yet.
    case activationRequired(scheme: ActivationScheme, needs: CardActivationNeeds)

    /// PACE timed out at step 2/5 (likely card anti-tamper penalty delay).
    case secureChannelTimedOut

    /// PACE did not agree, so the digits describe a different card.
    case wrongCardAccessNumber
  }

#endif
