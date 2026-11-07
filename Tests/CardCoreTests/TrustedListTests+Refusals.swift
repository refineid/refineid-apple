// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// What the reader refuses: wrong signers, changed bytes, no
  /// signature, the wrong list type, and lists beyond a bound.
  extension TrustedListTests {
    /// The outcome of the served national list when `national` is
    /// handed out for its location.
    private static func outcome(
      _ fixture: TrustedListFixture,
      national: Data
    ) throws -> Result<TrustedList, TrustedLists.ListFailure> {
      let lists = try TrustedLists.read(
        listOfTheLists: try fixture.signedListOfTheLists(nextUpdate: TrustedListFixture.nextUpdate),
        signers: [fixture.listOfTheLists.certificate],
        national: { location in location == TrustedListFixture.nationalLocation ? national : nil },
        fetchedAt: try TrustedListFixture.instant(TrustedListFixture.fetched)
      ).lists
      return try #require(
        lists.national.first { list in list.territory == TrustedListFixture.territory }
      ).outcome
    }

    @Test
    internal func aListSignedByAnUnlistedKeyIsRefused() throws {
      let fixture = try TrustedListFixture()
      let unlisted = try TrustedListFixture.signed(
        TrustedListFixture.nationalXml(services: fixture.services()), by: fixture.listOfTheLists)
      #expect(
        try Self.outcome(fixture, national: unlisted) == .failure(.unreadable(.signerNotEntitled)))
      #expect(throws: TrustedListError.signerNotEntitled) {
        try TrustedList.read(
          try fixture.signedListOfTheLists(nextUpdate: nil),
          signers: [fixture.national.certificate])
      }
      #expect(throws: TrustedListError.signerNotEntitled) {
        try TrustedList.read(try fixture.signedListOfTheLists(nextUpdate: nil), signers: [])
      }
    }

    @Test
    internal func aChangedListFailsItsSignature() throws {
      let fixture = try TrustedListFixture()
      let signed = try #require(
        String(data: try fixture.signedNationalList(services: fixture.services()), encoding: .utf8))
      let changed = signed.replacingOccurrences(
        of: TrustedListFixture.nationalOperator, with: "Another Supervisory Body")
      #expect(changed != signed)
      #expect(
        try Self.outcome(fixture, national: Data(changed.utf8))
          == .failure(.unreadable(.signatureInvalid)))
    }

    @Test
    internal func anUnsignedListIsRefused() throws {
      let fixture = try TrustedListFixture()
      let unsigned = Data(TrustedListFixture.nationalXml(services: fixture.services()).utf8)
      #expect(try Self.outcome(fixture, national: unsigned) == .failure(.unreadable(.noSignature)))
    }

    @Test
    internal func aNationalListReadAsTheListOfTheListsIsRefused() throws {
      let fixture = try TrustedListFixture()
      #expect(throws: TrustedListError.notListOfTheLists) {
        try TrustedLists.read(
          listOfTheLists: try fixture.signedNationalList(services: fixture.services()),
          signers: [fixture.national.certificate],
          national: { _ in nil },
          fetchedAt: try TrustedListFixture.instant(TrustedListFixture.fetched))
      }
      let lotl = try fixture.signedListOfTheLists(nextUpdate: nil)
      #expect(
        try Self.outcome(fixture, national: lotl) == .failure(.unreadable(.signerNotEntitled)))
    }

    @Test
    internal func aServiceWithTooLongAHistoryIsRefused() throws {
      let fixture = try TrustedListFixture()
      let history = Array(
        repeating: (TrustService.Status.granted, TrustedListFixture.granted),
        count: TrustedList.maximumHistory + 1)
      let services = TrustedListFixture.service(
        type: TrustedListElement.qualifiedCertificatesType,
        name: TrustedListFixture.certificateService, certificate: fixture.hierarchy.issuing,
        current: (.granted, TrustedListFixture.granted), history: history)
      let long = try fixture.signedNationalList(services: services)
      #expect(try Self.outcome(fixture, national: long) == .failure(.unreadable(.bound(.history))))
    }

    @Test
    internal func aSignatureWithOtherThanTwoReferencesIsRefused() throws {
      let fixture = try TrustedListFixture()
      let signed = try #require(
        String(data: try fixture.signedNationalList(services: fixture.services()), encoding: .utf8))
      let marker = "</ds:SignedInfo>"
      let extra =
        "<ds:Reference URI=\"#ID0001\"><ds:DigestMethod Algorithm=\""
        + AsicVerification.XmlDigestMethod.sha256.uri + "\"/>"
        + "<ds:DigestValue>\(TrustedListFixture.digest(Data()))</ds:DigestValue></ds:Reference>"
      let three = signed.replacingOccurrences(of: marker, with: extra + marker)
      #expect(three != signed)
      guard
        case .failure(.unreadable(.malformed)) = try Self.outcome(
          fixture, national: Data(three.utf8))
      else {
        Issue.record("A signature with three references was not refused as malformed")
        return
      }
    }

    @Test
    internal func aSignerThisVerifierDoesNotKnowIsUnverifiable() throws {
      let fixture = try TrustedListFixture()
      let signed = try #require(
        String(data: try fixture.signedNationalList(services: fixture.services()), encoding: .utf8))
      let unknown = signed.replacingOccurrences(
        of: "xmldsig-more#ecdsa-sha256", with: "xmldsig-more#ecdsa-sha1")
      #expect(unknown != signed)
      guard
        case .failure(.unreadable(.unverifiable)) = try Self.outcome(
          fixture, national: Data(unknown.utf8))
      else {
        Issue.record("An unknown signature algorithm was not refused as unverifiable")
        return
      }
    }
  }

#endif
