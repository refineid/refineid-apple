// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import CardCore

  /// Reading synthetic trusted lists: what they yield and what they
  /// refuse.
  @Suite
  internal struct TrustedListTests {
    /// The pointers the synthetic list of the lists carries.
    private static let pointerCount = 5

    /// The national entries: the served, the unserved and the
    /// unfetchable list; the PDF form and the pointer to the list of
    /// the lists itself are not followed.
    private static let nationalCount = 3

    /// The records a reading of both lists yields.
    private static let cachedCount = 2

    /// The services the national list carries.
    private static let serviceCount = 3

    /// The list `territory` names among `lists`.
    private static func national(
      _ lists: TrustedLists,
      _ territory: String
    ) throws -> TrustedLists.NationalList {
      try #require(lists.national.first { list in list.territory == territory })
    }

    @Test
    internal func aSyntheticListOfTheListsReadsWithItsNationalList() throws {
      let fixture = try TrustedListFixture()
      let reading = try fixture.reading()
      let lists = reading.lists
      let lotl = lists.listOfTheLists
      #expect(lotl.kind == .euListOfTheLists)
      #expect(lotl.territory == TrustedListFixture.euTerritory)
      #expect(lotl.operatorName == TrustedListFixture.listOfTheListsOperator)
      #expect(lotl.signer == fixture.listOfTheLists.certificate)
      #expect(lotl.pointers.count == Self.pointerCount)
      #expect(lotl.pointers.filter(\.namesNationalList).count == Self.nationalCount)
      #expect(lotl.nextUpdate == (try TrustedListFixture.instant(TrustedListFixture.nextUpdate)))
      #expect(lists.fetchedAt == (try TrustedListFixture.instant(TrustedListFixture.fetched)))
      #expect(lists.national.count == Self.nationalCount)

      let served = try Self.national(lists, TrustedListFixture.territory)
      let list = try served.outcome.get()
      #expect(list.kind == .euGeneric)
      #expect(list.operatorName == TrustedListFixture.nationalOperator)
      #expect(list.signer == fixture.national.certificate)
      #expect(list.services.count == Self.serviceCount)
      let certificateService = try #require(
        list.services.first { service in service.kind == .qualifiedCertificates })
      #expect(certificateService.provider == TrustedListFixture.provider)
      #expect(certificateService.name == TrustedListFixture.certificateService)
      #expect(certificateService.certificates == [fixture.hierarchy.issuing])
      #expect(certificateService.unreadableCertificates == 0)
      let timeStamping = try #require(
        list.services.first { service in service.kind == .qualifiedTimeStamps })
      #expect(timeStamping.certificates == [fixture.hierarchy.authority.certificate])
      #expect(
        list.services.contains { service in
          service.kind == .other(TrustedListFixture.otherServiceType)
        })

      let unserved = try Self.national(lists, TrustedListFixture.unservedTerritory)
      #expect(unserved.outcome == .failure(.notFetched))
      let unfetchable = try Self.national(lists, TrustedListFixture.unfetchableTerritory)
      #expect(unfetchable.outcome == .failure(.noLocation))
      #expect(unfetchable.location == nil)

      #expect(reading.cache.count == Self.cachedCount)
      #expect(
        reading.cache.map(\.location) == [
          TrustedLists.listOfTheListsLocation, TrustedListFixture.nationalLocation,
        ])
      #expect(lists.validUntil == lotl.nextUpdate)
      #expect(!lists.isStale(at: lists.fetchedAt))
    }

    @Test
    internal func grantedPeriodsFollowTheStatusHistory() throws {
      let fixture = try TrustedListFixture()
      let list = try Self.national(try fixture.reading().lists, TrustedListFixture.territory)
        .outcome.get()
      let supervised = try TrustedListFixture.instant(TrustedListFixture.supervised)
      let granted = try TrustedListFixture.instant(TrustedListFixture.granted)
      let withdrawn = try TrustedListFixture.instant(TrustedListFixture.withdrawn)
      let certificateService = try #require(
        list.services.first { service in service.kind == .qualifiedCertificates })
      #expect(certificateService.grantedPeriods == [GrantedPeriod(start: supervised, until: nil)])
      let timeStamping = try #require(
        list.services.first { service in service.kind == .qualifiedTimeStamps })
      #expect(timeStamping.grantedPeriods == [GrantedPeriod(start: granted, until: withdrawn)])
      let other = try #require(
        list.services.first { service in
          service.kind != .qualifiedCertificates && service.kind != .qualifiedTimeStamps
        })
      #expect(other.anchors.isEmpty)
    }

    @Test
    internal func theAnchorsNameTheListedServicesForTheirRolesAndPeriods() throws {
      let fixture = try TrustedListFixture()
      let anchors = try fixture.anchors()
      let whileGranted = try DocumentTrustFixture.instant(TrustedListFixture.whileGranted)
      let afterWithdrawal = try DocumentTrustFixture.instant(TrustedListFixture.afterWithdrawal)
      #expect(anchors.anchors.count == Self.cachedCount)
      #expect(
        anchors.certificates(for: .certificateIssuing, at: whileGranted)
          == [fixture.hierarchy.issuing])
      #expect(anchors.certificates(for: .timeStamping, at: afterWithdrawal).isEmpty)
      #expect(
        anchors.certificates(for: .timeStamping, at: whileGranted)
          == [fixture.hierarchy.authority.certificate])
      #expect(anchors.certificates(for: .certificateIssuing, at: .distantPast).isEmpty)
      #expect(anchors.fetchedAt == (try TrustedListFixture.instant(TrustedListFixture.fetched)))
      #expect(
        anchors.listsValidUntil == (try TrustedListFixture.instant(TrustedListFixture.nextUpdate)))
    }

    @Test
    internal func aStaleListStillAnchorsAndSaysSo() throws {
      let fixture = try TrustedListFixture()
      let lists = try fixture.reading().lists
      let anchors = TrustAnchors(trustedLists: lists)
      let later = try TrustedListFixture.instant(TrustedListFixture.afterNextUpdate)
      #expect(lists.isStale(at: later))
      #expect(anchors.isStale(at: later))
      #expect(!anchors.isStale(at: lists.fetchedAt))
      #expect(!anchors.anchors.isEmpty)
    }

    @Test
    internal func aClosedListNeverGoesStale() throws {
      let fixture = try TrustedListFixture()
      let closed = try fixture.signedListOfTheLists(nextUpdate: nil)
      let lotl = try TrustedList.read(closed, signers: [fixture.listOfTheLists.certificate])
      #expect(lotl.nextUpdate == nil)
      #expect(!lotl.isStale(at: .distantFuture))
    }

    @Test
    internal func theCacheReadsBackToTheSameLists() throws {
      let fixture = try TrustedListFixture()
      let reading = try fixture.reading()
      let again = try TrustedLists.fromCache(
        reading.cache, signers: [fixture.listOfTheLists.certificate])
      #expect(TrustAnchors(trustedLists: again) == TrustAnchors(trustedLists: reading.lists))
      #expect(again.national.count == reading.lists.national.count)
      #expect(again.fetchedAt == reading.lists.fetchedAt)
      #expect(throws: TrustedListError.notFetched) {
        try TrustedLists.fromCache(
          Array(reading.cache.dropFirst()), signers: [fixture.listOfTheLists.certificate])
      }
    }
  }

#endif
