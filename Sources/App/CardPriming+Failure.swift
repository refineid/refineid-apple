// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import CardCore

  extension CardPriming {
    /// Why a priming run stopped short.
    internal enum Failure: Error {
      /// The card still needs its first holder PIN values.
      ///
      /// Carries what the live card reported, so the caller can open the
      /// activation route it names without reading the card again.
      case activationRequired(scheme: ActivationScheme, needs: CardActivationNeeds)

      /// No card access number is stored, so PACE cannot be run.
      case cardAccessNumberMissing

      /// The certificate came off the card but is not a certificate.
      case certificateUnreadable

      /// One or two attempts remain. The exact card-reported count survives
      /// into the UI instead of being collapsed into an opaque safety error.
      case pin1LowAttempts(RetryCount)

      /// PIN1 does not fit its digit rules, so there is nothing to store.
      ///
      /// Shape is a property of the value and is checked before the slot
      /// opens. Whether the card accepts it is a property of the card at
      /// the instant it signs, and is checked there.
      case pin1Malformed

      /// PIN1 was malformed or its retry counter could not be read.
      case pin1Unavailable

      /// The prime could not be written, so nothing would be there to
      /// serve the next login.
      case primeNotStored

      /// The slot reported no answer to reset, so the card cannot be
      /// named -- and an unnamed card would be served another card's
      /// primed identity.
      case unidentifiedCard

      /// The card refused the offered access number, so this is a
      /// different card than the digits describe.
      case wrongCardAccessNumber
    }
  }

#endif
