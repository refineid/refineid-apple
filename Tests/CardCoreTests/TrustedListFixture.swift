// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CryptoKit
  import Foundation
  import Security
  import Testing

  @testable import CardCore

  /// A synthetic list of the lists and the national list it points at,
  /// signed with test keys the way TS 119 612 annex B.1 says: an
  /// enveloped reference to the list under the enveloped-signature
  /// transform and exclusive canonicalisation, and a reference to the
  /// signed properties.
  internal struct TrustedListFixture {
    /// One signer of a list: its key and certificate.
    internal struct Operator {
      /// The private key.
      internal let key: SecKey

      /// The self-signed certificate, DER.
      internal let certificate: Data

      /// The key and signature kind.
      internal let kind: CertificateRevocationListFixtures.SignatureKind
    }

    /// The territory of the list of the lists.
    internal static let euTerritory = "EU"

    /// The territory of the national list.
    internal static let territory = "FI"

    /// Where the national list is served.
    internal static let nationalLocation = "https://trusted-list.example/fi.xml"

    /// Where its human-readable form is served.
    internal static let nationalPdfLocation = "https://trusted-list.example/fi.pdf"

    /// A list nobody serves.
    internal static let unservedLocation = "https://trusted-list.example/xx.xml"

    /// A territory whose list nobody serves.
    internal static let unservedTerritory = "XX"

    /// A location the shell does not fetch.
    internal static let unfetchableLocation = "ftp://trusted-list.example/yy.xml"

    /// A territory whose list has an unfetchable location.
    internal static let unfetchableTerritory = "YY"

    /// The operator of the list of the lists.
    internal static let listOfTheListsOperator = "Synthetic Commission"

    /// The operator of the national list.
    internal static let nationalOperator = "Synthetic Supervisory Body"

    /// The provider of the listed services.
    internal static let provider = "Synthetic Trust Services Oy"

    /// The listed certificate service.
    internal static let certificateService = "Synthetic Qualified CA"

    /// The listed time-stamping service.
    internal static let timeStampingService = "Synthetic Qualified TSU"

    /// A service type no anchor is taken from.
    internal static let otherServiceType = "http://uri.etsi.org/TrstSvc/Svctype/CA/PKC"

    /// The media type of the human-readable form.
    internal static let pdfMediaType = "application/pdf"

    /// When every list was issued.
    internal static let issued = "2026-01-01T00:00:00Z"

    /// When every list is next due.
    internal static let nextUpdate = "2026-07-01T00:00:00Z"

    /// When the lists were fetched.
    internal static let fetched = "2026-02-01T00:00:00Z"

    /// After every list's next update.
    internal static let afterNextUpdate = "2026-08-01T00:00:00Z"

    /// When the certificate service came under supervision, before the
    /// Directive regime ended.
    internal static let supervised = "2015-01-01T00:00:00Z"

    /// When the services were granted: the end of the Directive regime.
    internal static let granted = "2016-07-01T00:00:00Z"

    /// When the time-stamping service was withdrawn.
    internal static let withdrawn = "2026-03-01T00:00:00Z"

    /// Inside the time-stamping service's granted period.
    internal static let whileGranted = "20260201000000Z"

    /// After the time-stamping service's withdrawal.
    internal static let afterWithdrawal = "20260401000000Z"

    /// The `Id` of the signed properties.
    internal static let propertiesId = "xades-signed-properties"

    /// The `Id` of the signature.
    internal static let signatureId = "list-signature"

    /// The signer of the list of the lists, RSA.
    internal let listOfTheLists: Operator

    /// The signer of the national list, ECDSA P-256.
    internal let national: Operator

    /// The hierarchy whose issuing CA and authority the national list
    /// names.
    internal let hierarchy: DocumentTrustFixture

    /// Fresh operators and a fresh hierarchy.
    internal init() throws {
      listOfTheLists = try Self.makeOperator(Self.listOfTheListsOperator, kind: .rsaSha256)
      national = try Self.makeOperator(Self.nationalOperator, kind: .ecdsaSha256)
      hierarchy = try DocumentTrustFixture()
    }

    /// The instant one `xsd:dateTime` names.
    internal static func instant(_ dateTime: String) throws -> Date {
      try #require(XmlDateTime.instant(dateTime))
    }

    /// A self-signed list operator.
    private static func makeOperator(
      _ commonName: String,
      kind: CertificateRevocationListFixtures.SignatureKind
    ) throws -> Operator {
      let key = try CertificateRevocationListFixtures.makeKey(for: kind)
      let certificate = try CertificateRevocationListFixtures.certificate(
        description: .init(
          allowsCrlSigning: false,
          includesKeyUsage: true,
          malformedKeyUsage: false,
          commonName: commonName,
          isCertificateAuthority: false,
          issuerName: CertificateRevocationListFixtures.name(commonName),
          serial: Data(commonName.utf8.prefix(1))
        ),
        publicKey: key, signer: key, kind: kind
      )
      return Operator(key: key, certificate: certificate, kind: kind)
    }

    /// The signed list of the lists, pointing at the national list.
    internal func signedListOfTheLists(nextUpdate: String?) throws -> Data {
      try Self.signed(
        Self.listOfTheListsXml(nationalSigner: national.certificate, nextUpdate: nextUpdate),
        by: listOfTheLists)
    }

    /// The signed national list carrying `services`.
    internal func signedNationalList(services: String) throws -> Data {
      try Self.signed(Self.nationalXml(services: services), by: national)
    }

    /// The services the national list carries: the hierarchy's issuing
    /// CA, granted since `granted` after supervision since
    /// `supervised`; the hierarchy's authority, withdrawn since
    /// `withdrawn` after being granted since `granted`; and a service
    /// of another type.
    internal func services() -> String {
      Self.service(
        type: TrustedListElement.qualifiedCertificatesType, name: Self.certificateService,
        certificate: hierarchy.issuing, current: (.granted, Self.granted),
        history: [(.underSupervision, Self.supervised)])
        + Self.service(
          type: TrustedListElement.qualifiedTimeStampsType, name: Self.timeStampingService,
          certificate: hierarchy.authority.certificate, current: (.withdrawn, Self.withdrawn),
          history: [(.granted, Self.granted)])
        + Self.service(
          type: Self.otherServiceType, name: "Synthetic Validation Service",
          certificate: hierarchy.authority.certificate, current: (.granted, Self.granted),
          history: [])
    }

    /// The lists as a shell reads them after fetching both.
    internal func reading() throws -> TrustedLists.Reading {
      let nationalList = try signedNationalList(services: services())
      return try TrustedLists.read(
        listOfTheLists: try signedListOfTheLists(nextUpdate: Self.nextUpdate),
        signers: [listOfTheLists.certificate],
        national: { location in location == Self.nationalLocation ? nationalList : nil },
        fetchedAt: try Self.instant(Self.fetched)
      )
    }

    /// The anchors the lists yield.
    internal func anchors() throws -> TrustAnchors {
      TrustAnchors(trustedLists: try reading().lists)
    }
  }

#endif
