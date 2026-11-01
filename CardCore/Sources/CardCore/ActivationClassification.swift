// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Which card an activation is for and the FINEID S4-1 §4.6 scheme it
/// takes.
///
/// The card's credential reference numbering decides first: a card on
/// the FINEID S4-2 v4.0 §4.2 organization numbering is activated by the
/// §4.6.1 procedure, the activation PIN being its PUK, whatever its
/// certificates say. A card on the citizen numbering takes its scheme
/// from its authentication certificate's validity start.
public enum ActivationClassification: Hashable, Sendable {
  /// A citizen card under the scheme its certificate dates.
  case citizen(ActivationScheme)

  /// An organization card: §4.6.1 under the organization numbering.
  case organization

  /// The scheme the activation runs.
  public var scheme: ActivationScheme {
    switch self {
    case .citizen(let scheme):
      scheme

    case .organization:
      .activationCodeIsPuk
    }
  }

  /// Decides from the resolved numbering and, for a citizen card, the
  /// authentication certificate.
  ///
  /// Nil when a citizen card's certificate validity start cannot be
  /// read: no scheme, and so no activation decision.
  public static func decide(
    numbering: CredentialReferenceSet,
    authenticationCertificateDER: Data?
  ) -> Self? {
    switch numbering {
    case .organization:
      .organization

    case .citizen:
      authenticationCertificateDER
        .flatMap(ActivationScheme.classify(authenticationCertificateDER:))
        .map(Self.citizen)
    }
  }
}

extension CardOperations {
  /// Classifies the card in session for activation, counter-safe.
  ///
  /// Resolves the reference numbering (remembered for the session) and,
  /// on a citizen card only, reads the authentication certificate unless
  /// the caller already holds it. Nil when either read fails.
  public func activationClassification(
    authenticationCertificate: Data? = nil
  ) -> ActivationClassification? {
    guard let numbering = try? resolveCredentialReferences() else {
      return nil
    }
    let certificate: Data?
    switch numbering {
    case .organization:
      certificate = nil

    case .citizen:
      certificate = authenticationCertificate ?? (try? readCertificate(.authentication))
    }
    return ActivationClassification.decide(
      numbering: numbering,
      authenticationCertificateDER: certificate
    )
  }
}
