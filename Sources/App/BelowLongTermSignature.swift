// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG

  import Foundation

  /// A development-build signature kept below the long-term archival
  /// level (B-LTA): the level it reached and why it went no further.
  ///
  /// Only `SignatureLevelPolicy.highestReached` produces one. Release and
  /// TestFlight builds contain none of this type.
  internal struct BelowLongTermSignature: Equatable, Sendable {
    /// A baseline level below B-LTA (ETSI EN 319 142-1 and
    /// EN 319 132-1, clause 6.3).
    internal enum Level: Equatable, Sendable {
      /// The card signature and its certificate, with no timestamp.
      case basic

      /// The card signature with its signature timestamp.
      case timestamped

      /// The timestamped signature with its validation material, but
      /// no archive timestamp.
      case longTerm

      /// The level's name in the baseline profiles.
      internal var label: String {
        switch self {
        case .basic:
          BelowLongTermSignature.basicLabel

        case .timestamped:
          BelowLongTermSignature.timestampedLabel

        case .longTerm:
          BelowLongTermSignature.longTermLabel
        }
      }
    }

    /// Why the long-term archival level was not reached.
    internal enum Cause: Equatable, Sendable {
      /// The signature timestamp could not be obtained.
      case signatureTimestamp

      /// The archive timestamp could not be obtained.
      case archiveTimestamp

      /// No certificate was found that issued one in the path.
      case issuerUnavailable

      /// The signer path has no approved anchor.
      case trustAnchorUnavailable

      /// No authenticated current status answer was available.
      case revocationUnavailable

      /// An authenticated status answer says a path certificate is revoked.
      case revoked

      /// Any other failure while collecting or storing the evidence.
      case evidence

      /// The cause of a failed stage above the signature timestamp.
      internal init(afterTimestamp error: Error) {
        switch error {
        case DocumentSigner.Failure.network:
          self = .archiveTimestamp

        case DocumentSigner.Failure.validation(let evidence):
          self = Self(collecting: evidence)

        default:
          self = .evidence
        }
      }

      /// The cause named by the evidence collector's failure.
      private init(collecting error: Error) {
        switch error as? ValidationMaterialCollector.Failure {
        case .issuerUnavailable:
          self = .issuerUnavailable

        case .trustAnchorUnavailable:
          self = .trustAnchorUnavailable

        case .revocationUnavailable:
          self = .revocationUnavailable

        case .revoked:
          self = .revoked

        default:
          self = .evidence
        }
      }
    }

    /// ETSI's name for the basic level.
    internal static let basicLabel = "B-B"

    /// ETSI's name for the timestamped level.
    internal static let timestampedLabel = "B-T"

    /// ETSI's name for the level with validation material.
    internal static let longTermLabel = "B-LT"

    /// What a development output's name carries before the level.
    internal static let nameMarkerPrefix = "-dev-"

    /// The baseline family of a PAdES signature.
    private static let padesFamily = "PAdES"

    /// The baseline family of the XAdES signature in a container.
    private static let xadesFamily = "XAdES"

    /// Joins the family to the level in a level's full name.
    private static let familySeparator = " "

    /// The signature's format.
    internal let format: SignatureFormat

    /// The level the saved bytes carry.
    internal let level: Level

    /// Why it stopped there.
    internal let cause: Cause

    /// The marker the output's name carries before its extension, as in
    /// `-dev-B-T`.
    internal var nameMarker: String {
      Self.nameMarkerPrefix + level.label
    }

    /// The level's full name, as in `PAdES B-T`.
    internal var levelName: String {
      let family = format == .pades ? Self.padesFamily : Self.xadesFamily
      return family + Self.familySeparator + level.label
    }

    /// What the holder is told beside the saved output.
    internal var notice: String {
      String(format: noticeFormat, levelName, nameMarker, causeText)
    }

    /// The notice's sentence: what a level below B-LT lacks is the
    /// validation material, and what B-LT lacks is the archive
    /// timestamp.
    private var noticeFormat: String {
      switch level {
      case .basic, .timestamped:
        Self.text(
          "dev.belowLongTerm",
          """
          Development build: saved as %1$@ without long-term validation material; \
          the file name ends in %2$@. Reason: %3$@.
          """
        )

      case .longTerm:
        Self.text(
          "dev.belowArchival",
          """
          Development build: saved as %1$@ without an archive timestamp; \
          the file name ends in %2$@. Reason: %3$@.
          """
        )
      }
    }

    /// The cause as a clause.
    private var causeText: String {
      switch cause {
      case .signatureTimestamp:
        Self.text(
          "dev.cause.signatureTimestamp", "no valid signature timestamp was obtained")

      case .archiveTimestamp:
        Self.text("dev.cause.archiveTimestamp", "no valid archive timestamp was obtained")

      case .issuerUnavailable:
        Self.text("dev.cause.issuer", "the issuer of the certificate could not be found")

      case .trustAnchorUnavailable:
        Self.text("dev.cause.trustAnchor", "no trusted root certificate was available")

      case .revocationUnavailable:
        Self.text(
          "dev.cause.revocation",
          "the revocation status of the certificate could not be fetched")

      case .revoked:
        Self.text("dev.cause.revoked", "a certificate in the chain is revoked")

      case .evidence:
        Self.text(
          "dev.cause.evidence", "the material for long-term validation could not be collected")
      }
    }

    private static func text(
      _ key: StaticString,
      _ fallback: String.LocalizationValue
    ) -> String {
      String(localized: key, defaultValue: fallback, table: "DocumentSigning")
    }
  }

#endif
