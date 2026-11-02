// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import CardCore
  import Foundation
  import Security

  /// The card this phone was set up with, as its prime records it.
  ///
  /// A personal card's prime carries the card access number its PACE
  /// opens with. An organization card's carries none: its PACE password
  /// is the PIN each operation spends (FINEID S1 v4.0, organizational
  /// cards, section 2.1), so its prime holds the certificates and the chip
  /// serial only, and every operation on it opens its own channel with its
  /// own PIN.
  internal enum PhoneCardPrime: Sendable {
    /// An organization card, opened with the PIN an operation spends.
    case organization(OrganizationPrime)

    /// A personal card, opened with its card access number.
    case personal(PrimedIdentity)

    /// The prime the phone serves: a personal card's first, else an
    /// organization card's.
    internal static var current: Self? {
      if let personal = PrimeStore.storedIdentities().first {
        return .personal(personal)
      }
      return OrganizationPrimeStore.storedPrimes().first.map(Self.organization)
    }

    /// Whether the phone holds any prime.
    internal static var isStored: Bool {
      PrimeStore.storedCount() > 0 || !OrganizationPrimeStore.storedPrimes().isEmpty
    }

    /// The holder the served prime names, formatted as the identity row
    /// shows it, or nil when its certificate will not parse.
    internal static var holderName: String? {
      guard let certificate = current?.authenticationCertificate else { return nil }
      if let formatted = DistinguishedName.holderLine(fromCertificate: certificate) {
        return formatted
      }
      guard let parsed = SecCertificateCreateWithData(nil, certificate as CFData) else {
        return nil
      }
      return SecCertificateCopySubjectSummary(parsed) as String?
    }

    /// The authentication certificate.
    internal var authenticationCertificate: Data {
      switch self {
      case .personal(let identity):
        identity.certDER

      case .organization(let prime):
        prime.certificateDER
      }
    }

    /// The qualified signature certificate, when the prime holds one.
    internal var signatureCertificate: Data? {
      switch self {
      case .personal(let identity):
        identity.signatureCertDER

      case .organization(let prime):
        prime.signatureCertificateDER
      }
    }

    /// Whether operations open the card with their own PIN.
    internal var opensWithPin: Bool {
      if case .organization = self { return true }
      return false
    }
  }

#endif
