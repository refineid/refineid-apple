// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation

  @testable import CardCore

  /// The unsigned XML of the synthetic lists, in the shape the
  /// Commission's list has.
  extension TrustedListFixture {
    /// The document element, with the namespace declarations the
    /// Commission's list carries, around `body`.
    internal static func document(_ body: String) -> String {
      #"<?xml version="1.0" encoding="UTF-8" standalone="no"?>"#
        + #"<TrustServiceStatusList xmlns="\#(TrustedListElement.namespace)" "#
        + #"xmlns:ns2="\#(XadesSignature.namespaceDsig)" "#
        + #"xmlns:ns3="\#(TrustedListElement.additionalTypesNamespace)" "#
        + #"xmlns:ns4="\#(XadesSignature.namespaceXades)" "#
        + #"Id="ID0001" TSLTag="http://uri.etsi.org/19612/TSLTag">"#
        + body + "\n</TrustServiceStatusList>"
    }

    /// The scheme information every list shares.
    internal static func schemeInformation(
      kind: String,
      territory: String,
      operatorName: String,
      nextUpdate: String?,
      pointers: String
    ) -> String {
      let due = nextUpdate.map { due in "<dateTime>\(due)</dateTime>" } ?? ""
      return """

        <SchemeInformation>
          <TSLVersionIdentifier>6</TSLVersionIdentifier>
          <TSLSequenceNumber>1</TSLSequenceNumber>
          <TSLType>\(kind)</TSLType>
          <SchemeOperatorName>
            <Name xml:lang="fi">Toimija</Name>
            <Name xml:lang="en">\(operatorName)</Name>
          </SchemeOperatorName>
          <SchemeName><Name xml:lang="en">\(territory):Synthetic trusted list</Name></SchemeName>
          <SchemeTerritory>\(territory)</SchemeTerritory>
          <HistoricalInformationPeriod>65535</HistoricalInformationPeriod>
          \(pointers)
          <ListIssueDateTime>\(Self.issued)</ListIssueDateTime>
          <NextUpdate>\(due)</NextUpdate>
          <DistributionPoints><URI>https://trusted-list.example/\(territory).xml</URI></DistributionPoints>
        </SchemeInformation>
        """
    }

    /// A `ServiceDigitalIdentity` over one certificate.
    internal static func identity(_ certificate: Data) -> String {
      "<ServiceDigitalIdentity><DigitalId><X509Certificate>"
        + certificate.base64EncodedString()
        + "</X509Certificate></DigitalId></ServiceDigitalIdentity>"
    }

    /// One `OtherTSLPointer`.
    internal static func pointer(
      location: String,
      territory: String,
      kind: String,
      mediaType: String,
      signer: Data
    ) -> String {
      """

          <OtherTSLPointer>
            <ServiceDigitalIdentities>\(Self.identity(signer))</ServiceDigitalIdentities>
            <TSLLocation>\(location)</TSLLocation>
            <AdditionalInformation>
              <OtherInformation><TSLType>\(kind)</TSLType></OtherInformation>
              <OtherInformation><SchemeTerritory>\(territory)</SchemeTerritory></OtherInformation>
              <OtherInformation><ns3:MimeType>\(mediaType)</ns3:MimeType></OtherInformation>
            </AdditionalInformation>
          </OtherTSLPointer>
      """
    }

    /// One `TSPService`, its history entries newest first as lists
    /// write them.
    internal static func service(
      type: String,
      name: String,
      certificate: Data,
      current: (TrustService.Status, String),
      history: [(TrustService.Status, String)]
    ) -> String {
      let entries = history.map { status, since in
        "<ServiceHistoryInstance><ServiceTypeIdentifier>\(type)</ServiceTypeIdentifier>"
          + #"<ServiceName><Name xml:lang="en">\#(name)</Name></ServiceName>"#
          + "<ServiceDigitalIdentity><DigitalId><X509SubjectName>CN=\(name)</X509SubjectName>"
          + "</DigitalId></ServiceDigitalIdentity>"
          + "<ServiceStatus>\(status.uri)</ServiceStatus>"
          + "<StatusStartingTime>\(since)</StatusStartingTime></ServiceHistoryInstance>"
      }
      let instances = entries.joined()
      let serviceHistory = instances.isEmpty ? "" : "<ServiceHistory>\(instances)</ServiceHistory>"
      return
        "<TSPService><ServiceInformation><ServiceTypeIdentifier>\(type)</ServiceTypeIdentifier>"
        + #"<ServiceName><Name xml:lang="fi">Palvelu</Name><Name xml:lang="en">\#(name)</Name>"#
        + "</ServiceName>" + Self.identity(certificate)
        + "<ServiceStatus>\(current.0.uri)</ServiceStatus>"
        + "<StatusStartingTime>\(current.1)</StatusStartingTime></ServiceInformation>"
        + serviceHistory + "</TSPService>"
    }

    /// An unsigned list of the lists pointing at itself, at the national
    /// list signed by `nationalSigner`, at its PDF form, at a list
    /// nobody serves and at one with an unfetchable location.
    internal static func listOfTheListsXml(nationalSigner: Data, nextUpdate: String?) -> String {
      let pointers = [
        Self.pointer(
          location: TrustedLists.listOfTheListsLocation, territory: Self.euTerritory,
          kind: TrustedListElement.euListOfTheListsType,
          mediaType: TrustedListElement.xmlMediaType, signer: nationalSigner),
        Self.pointer(
          location: Self.nationalPdfLocation, territory: Self.territory,
          kind: TrustedListElement.euGenericType, mediaType: Self.pdfMediaType,
          signer: nationalSigner),
        Self.pointer(
          location: Self.nationalLocation, territory: Self.territory,
          kind: TrustedListElement.euGenericType, mediaType: TrustedListElement.xmlMediaType,
          signer: nationalSigner),
        Self.pointer(
          location: Self.unservedLocation, territory: Self.unservedTerritory,
          kind: TrustedListElement.euGenericType, mediaType: TrustedListElement.xmlMediaType,
          signer: nationalSigner),
        Self.pointer(
          location: Self.unfetchableLocation, territory: Self.unfetchableTerritory,
          kind: TrustedListElement.euGenericType, mediaType: TrustedListElement.xmlMediaType,
          signer: nationalSigner),
      ].joined()
      return Self.document(
        Self.schemeInformation(
          kind: TrustedListElement.euListOfTheListsType, territory: Self.euTerritory,
          operatorName: Self.listOfTheListsOperator, nextUpdate: nextUpdate,
          pointers: "<PointersToOtherTSL>\(pointers)</PointersToOtherTSL>"))
    }

    /// An unsigned national list carrying `services`.
    internal static func nationalXml(services: String) -> String {
      let scheme = Self.schemeInformation(
        kind: TrustedListElement.euGenericType, territory: Self.territory,
        operatorName: Self.nationalOperator, nextUpdate: Self.nextUpdate, pointers: "")
      return Self.document(
        scheme + "<TrustServiceProviderList><TrustServiceProvider><TSPInformation><TSPName>"
          + #"<Name xml:lang="en">\#(Self.provider)</Name></TSPName></TSPInformation>"#
          + "<TSPServices>\(services)</TSPServices></TrustServiceProvider>"
          + "</TrustServiceProviderList>")
    }
  }

#endif
