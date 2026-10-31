// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The element names and paths the parser matches.
extension XadesXmlParser {
  /// Local names of the XML-DSig and XAdES elements the parser reads.
  internal enum Element {
    internal static let signature = "Signature"
    internal static let signedInfo = "SignedInfo"
    internal static let canonicalizationMethod = "CanonicalizationMethod"
    internal static let signatureMethod = "SignatureMethod"
    internal static let reference = "Reference"
    internal static let transforms = "Transforms"
    internal static let transform = "Transform"
    internal static let digestMethod = "DigestMethod"
    internal static let digestValue = "DigestValue"
    internal static let signatureValue = "SignatureValue"
    internal static let keyInfo = "KeyInfo"
    internal static let x509Data = "X509Data"
    internal static let x509Certificate = "X509Certificate"
    internal static let object = "Object"
    internal static let qualifyingProperties = "QualifyingProperties"
    internal static let signedProperties = "SignedProperties"
    internal static let unsignedProperties = "UnsignedProperties"
    internal static let unsignedSignatureProperties = "UnsignedSignatureProperties"
    internal static let signatureTimeStamp = "SignatureTimeStamp"
    internal static let encapsulatedTimeStamp = "EncapsulatedTimeStamp"
    internal static let certificateValues = "CertificateValues"
    internal static let encapsulatedX509Certificate = "EncapsulatedX509Certificate"
    internal static let revocationValues = "RevocationValues"
    internal static let crlValues = "CRLValues"
    internal static let encapsulatedCrlValue = "EncapsulatedCRLValue"
    internal static let ocspValues = "OCSPValues"
    internal static let encapsulatedOcspValue = "EncapsulatedOCSPValue"
    internal static let timeStampValidationData = "TimeStampValidationData"
    internal static let signedSignatureProperties = "SignedSignatureProperties"
    internal static let signingCertificate = "SigningCertificate"
    internal static let signingCertificateV2 = "SigningCertificateV2"
    internal static let cert = "Cert"
    internal static let certDigest = "CertDigest"
    internal static let issuerSerialV2 = "IssuerSerialV2"
    internal static let issuerSerial = "IssuerSerial"
    internal static let x509IssuerName = "X509IssuerName"
    internal static let x509SerialNumber = "X509SerialNumber"
  }

  /// Element paths below the owning `ds:Signature`.
  internal enum Path {
    internal static let signedInfo = [Element.signedInfo]
    internal static let canonicalizationMethod = [
      Element.signedInfo, Element.canonicalizationMethod,
    ]
    internal static let signatureMethod = [Element.signedInfo, Element.signatureMethod]
    internal static let reference = [Element.signedInfo, Element.reference]
    internal static let transform = reference + [Element.transforms, Element.transform]
    internal static let digestMethod = reference + [Element.digestMethod]
    internal static let digestValue = reference + [Element.digestValue]
    internal static let signatureValue = [Element.signatureValue]
    internal static let keyInfoCertificate = [
      Element.keyInfo, Element.x509Data, Element.x509Certificate,
    ]
    internal static let qualifyingProperties = [Element.object, Element.qualifyingProperties]
    internal static let signedProperties = qualifyingProperties + [Element.signedProperties]
    internal static let unsignedSignatureProperties =
      qualifyingProperties + [Element.unsignedProperties, Element.unsignedSignatureProperties]

    /// `xades:SignatureTimeStamp` tokens (EN 319 132-1 clause 5.3).
    internal static let signatureTimestampToken =
      unsignedSignatureProperties + [Element.signatureTimeStamp, Element.encapsulatedTimeStamp]

    /// The validation-data containers that hold certificates and
    /// revocation values: the signature's own, and the XAdES 1.4.1
    /// `TimeStampValidationData`.
    internal static let validationContainers = [
      unsignedSignatureProperties,
      unsignedSignatureProperties + [Element.timeStampValidationData],
    ]

    internal static let certificateValue = [
      Element.certificateValues, Element.encapsulatedX509Certificate,
    ]
    internal static let crlValue = [
      Element.revocationValues, Element.crlValues, Element.encapsulatedCrlValue,
    ]
    internal static let ocspValue = [
      Element.revocationValues, Element.ocspValues, Element.encapsulatedOcspValue,
    ]

    /// Each `xades:Cert` of a SigningCertificate or
    /// SigningCertificateV2 (EN 319 132-1 clause 5.2.2).
    internal static let signingCertificates = [
      Element.signingCertificateV2, Element.signingCertificate,
    ].map { property in
      signedProperties + [Element.signedSignatureProperties, property, Element.cert]
    }
  }
}
