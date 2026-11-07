// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One EU trusted list (ETSI TS 119 612 V2.3.1), read and verified: the
/// List of Trusted Lists the European Commission publishes or a national
/// list it points at.
///
/// `read(_:signers:)` is the border for one list: its enveloped XAdES
/// signature must verify under a certificate the caller names as
/// entitled to sign it (`TrustedListSignature`), and every field the
/// verifier consults is read once into typed facts. Bounds are named
/// constants; a list beyond one is refused whole.
///
/// Conformance: clause 5.3.3 (the list types), 5.3.13 (pointers),
/// 5.3.14 and 5.3.15 (issue time and next update), 5.5.1.1 (the service
/// types), 5.5.3 (a service's digital identity), 5.5.4, 5.5.5, 5.5.10
/// and 5.6 (statuses and their history), annex D.5.6 (status
/// identifiers), annex J (statuses held before Regulation (EU) No
/// 910/2014 applied).
public struct TrustedList: Sendable, Equatable {
  /// The type of a list (clause 5.3.3, annex D.5.1).
  public enum Kind: Sendable, Equatable {
    /// A member state's list of supervised trust services.
    case euGeneric

    /// The Commission's compiled list of pointers to the member
    /// states' lists.
    case euListOfTheLists

    /// The kind `uri` names.
    internal init?(uri: String) {
      switch uri {
      case TrustedListElement.euListOfTheListsType:
        self = .euListOfTheLists

      case TrustedListElement.euGenericType:
        self = .euGeneric

      default:
        return nil
      }
    }
  }

  /// Most bytes one list may have, 16 MiB: the largest national list is
  /// a few megabytes.
  public static let maximumBytes = 16_777_216

  /// Most pointers one list may carry: the list of the lists carries
  /// one or two per member state.
  public static let maximumPointers = 64

  /// Most signer certificates one pointer may carry (annex A.2 asks
  /// operators to publish a few with shifted validity).
  public static let maximumPointerSigners = 16

  /// Most services one list may carry: the largest national list has
  /// about a thousand.
  public static let maximumServices = 8_192

  /// Most history entries one service may carry.
  public static let maximumHistory = 64

  /// Most certificates one service digital identity may carry.
  ///
  /// They all represent one public key (clause 5.5.3); national lists
  /// in use list up to 13 renewals of one key in one identity.
  public static let maximumIdentityCertificates = 32

  /// Its type.
  public let kind: Kind

  /// The territory of its scheme.
  public let territory: String

  /// The scheme operator's name.
  public let operatorName: String

  /// When it was issued.
  public let issuedAt: Date

  /// By when the next update is due; nil for a closed list.
  public let nextUpdate: Date?

  /// Its pointers to other lists.
  public let pointers: [TrustedListPointer]

  /// The services it lists, in document order.
  public let services: [TrustService]

  /// The certificate that signed it, DER.
  public let signer: Data

  /// Reads and verifies one list: its signature must verify under one
  /// of `signers`, the certificates entitled to sign it.
  ///
  /// Throws `TrustedListError` when the bytes are not a well-formed
  /// list inside the bounds, or the signature does not verify under
  /// `signers`.
  public static func read(_ bytes: Data, signers: [Data]) throws -> Self {
    guard bytes.count <= Self.maximumBytes else { throw TrustedListError.tooLarge }
    let document: XmlDocument
    do {
      document = try XmlDocument(bytes)
    } catch let error as XmlReadError {
      throw TrustedListError.xml(error)
    }
    let root = document.root
    guard root.matches(TrustedListElement.namespace, TrustedListElement.trustServiceStatusList)
    else {
      throw TrustedListError.notTrustedList
    }
    let signatures = root.children(XadesSignature.namespaceDsig, XadesXmlParser.Element.signature)
    guard signatures.count == 1, let signature = signatures.first else {
      throw TrustedListError.noSignature
    }
    let signerCertificate = try TrustedListSignature.verify(
      document: document, root: root, signature: signature, signers: signers)
    guard
      let scheme = root.child(TrustedListElement.namespace, TrustedListElement.schemeInformation)
    else {
      throw TrustedListError.malformed("no SchemeInformation")
    }
    let information = try Self.schemeInformation(scheme)
    return Self(
      kind: information.kind,
      territory: information.territory,
      operatorName: information.operatorName,
      issuedAt: information.issuedAt,
      nextUpdate: information.nextUpdate,
      pointers: try Self.pointers(in: scheme),
      services: try Self.services(in: root),
      signer: signerCertificate
    )
  }

  /// Whether the list is past its next update at `now` (clause 5.3.15:
  /// such a list is expired).
  public func isStale(at now: Date) -> Bool {
    nextUpdate.map { due in due < now } ?? false
  }
}
