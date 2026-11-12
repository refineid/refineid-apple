// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD

  import CardCore
  import Foundation

  extension CardPriming {
    /// A setup credential bound to the selected card kind at entry time.
    ///
    /// Reflection never exposes the credential, and neither kind can be
    /// reinterpreted as the other after a card response or setting change.
    internal enum SetupCredential: Sendable {
      case personal(ProvenAccessNumber)
      case organization(Pin1Entry)
    }

    internal struct SetupEntry: Sendable, CustomReflectable {

      private let credential: SetupCredential

      internal var kind: ContactlessCardKind {
        switch credential {
        case .personal:
          .personal
        case .organization:
          .organization
        }
      }

      internal var customMirror: Mirror {
        Mirror(self, children: [])
      }

      internal init?(digits: String, kind: ContactlessCardKind) {
        switch kind {
        case .personal:
          guard let number = CardAccessNumber(digits: digits) else { return nil }
          credential = .personal(ProvenAccessNumber(value: number, digits: digits))
        case .organization:
          guard let pin = Pin1Entry(digits: digits) else { return nil }
          credential = .organization(pin)
        }
      }

      internal func personalAccessNumber() -> ProvenAccessNumber? {
        guard case .personal(let number) = credential else { return nil }
        return number
      }

      internal func organizationPin1() -> Pin1Entry? {
        guard case .organization(let pin) = credential else { return nil }
        return pin
      }
    }
  }

#endif
