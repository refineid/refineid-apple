// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The certificates carried inside a CMS SignedData (RFC 5652 §5.1).
///
/// A timestamp token embeds the authority's certificate and its chain,
/// because the request asked for them. A validator needs revocation
/// evidence for those as well as for the signer, so the signing side
/// has to be able to read them back out of the token it just received.
public enum CmsCertificates {
  /// The revocation evidence carried in SignedData's `crls [1]` field
  /// (RFC 5652 section 10.2.1).
  public struct RevocationInformation: Equatable, Sendable {
    /// Each CertificateList choice, as written.
    public let revocationLists: [Data]

    /// Each `id-ri-ocsp-response` other choice's OCSPResponse
    /// (RFC 5940 section 4.1).
    public let ocspResponses: [Data]
  }

  /// Every certificate in the token's `certificates [0]` field, in the
  /// order written, or an empty array when there are none.
  public static func inside(_ token: Data) -> [Data] {
    guard
      let signedData = CmsSignedData(in: token),
      let certificateSet = signedData.certificates
    else { return [] }
    var list = DerReader(token, within: certificateSet)
    var certificates: [Data] = []
    while let element = list.next() {
      // Only plain certificates; the other choices are attribute
      // certificates a validator does not want here.
      guard element.tag == DerValues.tagSequence else { continue }
      certificates.append(list.data(of: element))
    }
    return list.isAtEnd ? certificates : []
  }

  /// The CRLs and OCSP responses in SignedData's RevocationInfoChoices,
  /// empty when the field is absent or unreadable.
  ///
  /// Other formats than RFC 5940 OCSP responses are skipped.
  public static func revocationInformation(in token: Data) -> RevocationInformation {
    let empty = RevocationInformation(revocationLists: [], ocspResponses: [])
    guard
      let signedData = CmsSignedData(in: token),
      let choices = signedData.revocationChoices
    else { return empty }
    var list = DerReader(token, within: choices)
    var revocationLists: [Data] = []
    var ocspResponses: [Data] = []
    while let element = list.next() {
      switch element.tag {
      case DerValues.tagSequence:
        revocationLists.append(list.data(of: element))

      case DerValues.tagContext1Constructed:
        var other = DerReader(token, within: element)
        guard
          let format = other.next(),
          other.data(of: format)
            == DerEncoder.objectIdentifier(SignOids.otherRevocationInfoOcspResponse),
          let response = other.next(),
          response.tag == DerValues.tagSequence,
          other.isAtEnd
        else { continue }
        ocspResponses.append(other.data(of: response))

      default:
        continue
      }
    }
    guard list.isAtEnd else { return empty }
    return RevocationInformation(
      revocationLists: revocationLists, ocspResponses: ocspResponses
    )
  }

  /// Removes only SignedData's optional CertificateSet.
  ///
  /// SignerInfo does not cover this field, so a token verified before this
  /// operation keeps the same signed TSTInfo, attributes and signature. The
  /// enclosing lengths are rebuilt because the token becomes smaller.
  public static func removingCertificates(from token: Data) -> Data? {
    let encoded = Data(token)
    guard
      let parsed = CmsSignedData(in: encoded),
      let certificateSet = parsed.certificates
    else { return nil }
    var body = Data(
      encoded[
        parsed.element.content.lowerBound..<certificateSet.raw.lowerBound
      ]
    )
    body.append(
      encoded[
        certificateSet.raw.upperBound..<parsed.element.content.upperBound
      ]
    )
    let signedData = DerEncoder.tlv(DerValues.tagSequence, body)
    return DerEncoder.sequence([
      DerEncoder.objectIdentifier(SignOids.signedData),
      DerEncoder.tlv(DerValues.tagContext0Constructed, signedData),
    ])
  }
}
