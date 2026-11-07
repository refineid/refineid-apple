// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One trust service a list names (TS 119 612 clause 5.5).
public struct TrustService: Sendable, Equatable {
  /// What a listed service provides (clause 5.5.1).
  public enum Kind: Sendable, Equatable {
    /// A type no anchor is taken from, by its identifier.
    case other(String)

    /// Qualified certificates (`CA/QC`).
    case qualifiedCertificates

    /// Qualified time-stamps (`TSA/QTST`).
    case qualifiedTimeStamps

    /// The role an anchor taken from a service of this type plays.
    internal var anchorRole: TrustAnchor.Role? {
      switch self {
      case .other:
        nil

      case .qualifiedCertificates:
        .certificateIssuing

      case .qualifiedTimeStamps:
        .timeStamping
      }
    }

    /// The kind `uri` names.
    internal init(uri: String) {
      switch uri {
      case TrustedListElement.qualifiedCertificatesType:
        self = .qualifiedCertificates

      case TrustedListElement.qualifiedTimeStampsType:
        self = .qualifiedTimeStamps

      default:
        self = .other(uri)
      }
    }
  }

  /// The status of a listed service (annex D.5.6).
  public enum Status: Sendable, Equatable, CaseIterable {
    case accreditationCeased
    case accreditationRevoked
    case accredited
    case deprecatedAtNationalLevel
    case deprecatedByNationalLaw
    case granted
    case recognisedAtNationalLevel
    case setByNationalLaw
    case supervisionCeased
    case supervisionInCessation
    case supervisionRevoked
    case underSupervision
    case withdrawn

    /// The name under `TrustedListElement.statusPrefix`.
    internal var name: String {
      switch self {
      case .accreditationCeased:
        "accreditationceased"

      case .accreditationRevoked:
        "accreditationrevoked"

      case .accredited:
        "accredited"

      case .deprecatedAtNationalLevel:
        "deprecatedatnationallevel"

      case .deprecatedByNationalLaw:
        "deprecatedbynationallaw"

      case .granted:
        "granted"

      case .recognisedAtNationalLevel:
        "recognisedatnationallevel"

      case .setByNationalLaw:
        "setbynationallaw"

      case .supervisionCeased:
        "supervisionceased"

      case .supervisionInCessation:
        "supervisionincessation"

      case .supervisionRevoked:
        "supervisionrevoked"

      case .underSupervision:
        "undersupervision"

      case .withdrawn:
        "withdrawn"
      }
    }

    /// The identifier of this status.
    internal var uri: String { TrustedListElement.statusPrefix + name }

    /// Whether this is a status a qualified certificate service held
    /// under Directive 1999/93/EC that annex J (a) turned into
    /// `granted` when the Regulation applied.
    internal var isDirectiveGrant: Bool {
      self == .underSupervision || self == .supervisionInCessation || self == .accredited
    }

    /// The status `uri` names, nil for any other identifier.
    internal init?(uri: String) {
      guard let found = Self.allCases.first(where: { status in status.uri == uri }) else {
        return nil
      }
      self = found
    }
  }

  /// One status a service held, from when.
  public struct StatusEntry: Sendable, Equatable {
    /// The status.
    public let status: Status

    /// When it became effective.
    public let since: Date

    /// The service type the entry was recorded under.
    public let kind: Kind
  }

  /// The instant the Directive 1999/93/EC regime ended, 1 July 2016
  /// 00:00 UTC: Regulation (EU) No 910/2014 applies from then (its
  /// article 52(2)), and TS 119 612 annex J moved every service
  /// holding a status of the Directive to `granted` or `withdrawn`
  /// then.
  internal static let directiveRegimeEnd = Date(
    timeIntervalSince1970: TrustedListValues.directiveRegimeEndUnixTime)

  /// The provider's name.
  public let provider: String

  /// The service's name.
  public let name: String

  /// What it provides.
  public let kind: Kind

  /// The certificates representing its public key, the trust anchor it
  /// yields; empty for a type no anchor is taken from, or when none of
  /// them reads.
  public let certificates: [Data]

  /// How many certificates of its digital identity did not parse and
  /// were left out: nothing is anchored on them.
  public let unreadableCertificates: Int

  /// The current status, from when.
  public let current: StatusEntry

  /// The previous statuses, as listed.
  public let history: [StatusEntry]
}
