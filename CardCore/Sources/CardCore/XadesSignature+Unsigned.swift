// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The unsigned signature properties: timestamps and validation
/// material.
///
/// Nothing signs these, but an archive timestamp digests every one
/// that precedes it (EN 319 132-1 V1.3.1 clause 5.5.2.3 step 5), each
/// canonicalised on its own. So each is written in exclusive canonical
/// form like the signed subtrees: its root declares the prefix it
/// uses, and a descendant declares a prefix no ancestor in the subtree
/// renders.
extension XadesSignature {
  /// Which canonicalisation the verifier applies to the timestamped
  /// input.
  ///
  /// It names the one actually used, or the verifier hashes different
  /// bytes.
  private static var canonicalizationMethodElement: String {
    #"<ds:CanonicalizationMethod xmlns:ds="\#(namespaceDsig)" "#
      + #"Algorithm="\#(canonicalizationExclusive)">"#
      + "</ds:CanonicalizationMethod>"
  }

  /// The unsigned signature properties below the archive timestamp,
  /// in schema order, each without a trailing newline.
  ///
  /// Timestamps, then certificates, then revocation values, and
  /// inside those CRLs before OCSP responses (XAdES
  /// `RevocationValuesType`).
  internal static func unsignedSignaturePropertyElements(
    timestampTokens: [Data],
    material: PdfValidationStore.Material
  ) -> [String] {
    var elements = timestampTokens.enumerated().map { index, token in
      Self.signatureTimeStampElement(index: index, token: token)
    }
    if !material.certificates.isEmpty {
      elements.append(Self.certificateValuesElement(material.certificates))
    }
    if !material.revocationLists.isEmpty || !material.ocspResponses.isEmpty {
      elements.append(
        Self.revocationValuesElement(
          revocationLists: material.revocationLists,
          ocspResponses: material.ocspResponses
        )
      )
    }
    return elements
  }

  /// `xades:UnsignedProperties` around `properties`, or nothing when
  /// there are none.
  internal static func unsignedProperties(_ properties: [String]) -> String {
    guard !properties.isEmpty else { return "" }
    var out = "<xades:UnsignedProperties>\n"
    out += "<xades:UnsignedSignatureProperties>\n"
    for property in properties {
      out += property + "\n"
    }
    out += "</xades:UnsignedSignatureProperties>\n"
    out += "</xades:UnsignedProperties>\n"
    return out
  }

  /// One `xades:SignatureTimeStamp` over the signature value.
  private static func signatureTimeStampElement(index: Int, token: Data) -> String {
    #"<xades:SignatureTimeStamp xmlns:xades="\#(namespaceXades)" "#
      + #"Id="\#(signatureId)-TS-\#(index)">"# + "\n"
      + Self.canonicalizationMethodElement + "\n"
      + "<xades:EncapsulatedTimeStamp>"
      + token.base64EncodedString()
      + "</xades:EncapsulatedTimeStamp>\n"
      + "</xades:SignatureTimeStamp>"
  }

  /// The `xadesv141:ArchiveTimeStamp`, last of the unsigned signature
  /// properties (EN 319 132-1 V1.3.1 clause 5.5.2).
  ///
  /// Its children use two prefixes its root does not, so each
  /// declares its own.
  internal static func archiveTimeStampElement(_ token: Data) -> String {
    #"<xadesv141:ArchiveTimeStamp xmlns:xadesv141="\#(namespaceXades141)" "#
      + #"Id="\#(archiveTimestampId)">"# + "\n"
      + Self.canonicalizationMethodElement + "\n"
      + #"<xades:EncapsulatedTimeStamp xmlns:xades="\#(namespaceXades)">"#
      + token.base64EncodedString()
      + "</xades:EncapsulatedTimeStamp>\n"
      + "</xadesv141:ArchiveTimeStamp>"
  }

  /// `xades:CertificateValues` holding `certificates`.
  private static func certificateValuesElement(_ certificates: [Data]) -> String {
    var out = #"<xades:CertificateValues xmlns:xades="\#(namespaceXades)">"# + "\n"
    for certificate in certificates {
      out += "<xades:EncapsulatedX509Certificate>"
      out += certificate.base64EncodedString()
      out += "</xades:EncapsulatedX509Certificate>\n"
    }
    out += "</xades:CertificateValues>"
    return out
  }

  /// `xades:RevocationValues` holding the CRLs, then the OCSP
  /// responses.
  private static func revocationValuesElement(
    revocationLists: [Data],
    ocspResponses: [Data]
  ) -> String {
    var out = #"<xades:RevocationValues xmlns:xades="\#(namespaceXades)">"# + "\n"
    if !revocationLists.isEmpty {
      out += "<xades:CRLValues>\n"
      for list in revocationLists {
        out += "<xades:EncapsulatedCRLValue>"
        out += list.base64EncodedString()
        out += "</xades:EncapsulatedCRLValue>\n"
      }
      out += "</xades:CRLValues>\n"
    }
    if !ocspResponses.isEmpty {
      out += "<xades:OCSPValues>\n"
      for response in ocspResponses {
        out += "<xades:EncapsulatedOCSPValue>"
        out += response.base64EncodedString()
        out += "</xades:EncapsulatedOCSPValue>\n"
      }
      out += "</xades:OCSPValues>\n"
    }
    out += "</xades:RevocationValues>"
    return out
  }
}
