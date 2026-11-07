// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Reading the scheme information, pointers and services of one list.
extension TrustedList {
  /// What the `SchemeInformation` states about the list itself.
  internal struct SchemeInformation {
    internal let kind: Kind
    internal let territory: String
    internal let operatorName: String
    internal let issuedAt: Date
    internal let nextUpdate: Date?
  }

  /// The certificates of a digital identity and how many did not read.
  private struct Identity {
    let certificates: [Data]
    let unreadable: Int
  }

  /// The text of the one child `localName` of `parent` in the
  /// trusted-list namespace, trimmed.
  internal static func requiredText(_ parent: XmlElement, _ localName: String) throws -> String {
    guard let element = parent.child(TrustedListElement.namespace, localName) else {
      throw TrustedListError.malformed(localName)
    }
    return XadesXmlParser.trimmed(element.text)
  }

  /// Of the multilingual `Name` children of `names`, the English one,
  /// else the first (clause 5.1.4).
  internal static func preferredName(_ names: XmlElement) -> String? {
    let candidates = names.children(TrustedListElement.namespace, TrustedListElement.name)
    guard let first = candidates.first else { return nil }
    let english = candidates.first { name in
      name.xmlAttribute(XmlCanonicalizer.xmlLang) == TrustedListElement.english
    }
    return XadesXmlParser.trimmed((english ?? first).text)
  }

  /// The list type, territory, operator, issue time and next update.
  internal static func schemeInformation(_ scheme: XmlElement) throws -> SchemeInformation {
    guard let kind = Kind(uri: try Self.requiredText(scheme, TrustedListElement.tslType)) else {
      throw TrustedListError.unknownListType
    }
    let operatorElement = scheme.child(
      TrustedListElement.namespace, TrustedListElement.schemeOperatorName)
    guard let operatorName = operatorElement.flatMap(Self.preferredName) else {
      throw TrustedListError.malformed("no SchemeOperatorName")
    }
    guard
      let issuedAt = XmlDateTime.instant(
        try Self.requiredText(scheme, TrustedListElement.listIssueDateTime))
    else {
      throw TrustedListError.malformed("ListIssueDateTime is not a dateTime")
    }
    guard
      let nextUpdateElement = scheme.child(
        TrustedListElement.namespace, TrustedListElement.nextUpdate)
    else {
      throw TrustedListError.malformed("no NextUpdate")
    }
    var nextUpdate: Date?
    if let time = nextUpdateElement.child(TrustedListElement.namespace, TrustedListElement.dateTime)
    {
      guard let due = XmlDateTime.instant(time.text) else {
        throw TrustedListError.malformed("NextUpdate is not a dateTime")
      }
      nextUpdate = due
    }
    return SchemeInformation(
      kind: kind,
      territory: try Self.requiredText(scheme, TrustedListElement.schemeTerritory),
      operatorName: operatorName,
      issuedAt: issuedAt,
      nextUpdate: nextUpdate
    )
  }

  /// Every `OtherTSLPointer` of the scheme information, at most
  /// `maximumPointers`.
  internal static func pointers(in scheme: XmlElement) throws -> [TrustedListPointer] {
    let elements =
      scheme.child(TrustedListElement.namespace, TrustedListElement.pointersToOtherTsl)?
      .children(TrustedListElement.namespace, TrustedListElement.otherTslPointer) ?? []
    guard elements.count <= Self.maximumPointers else {
      throw TrustedListError.bound(.pointers)
    }
    return try elements.map(Self.pointer)
  }

  /// Every `TSPService` of every provider, at most `maximumServices`.
  internal static func services(in root: XmlElement) throws -> [TrustService] {
    var services: [TrustService] = []
    let providers =
      root.child(TrustedListElement.namespace, TrustedListElement.trustServiceProviderList)?
      .children(TrustedListElement.namespace, TrustedListElement.trustServiceProvider) ?? []
    for provider in providers {
      let information = provider.child(
        TrustedListElement.namespace, TrustedListElement.tspInformation)
      let nameElement = information?.child(TrustedListElement.namespace, TrustedListElement.tspName)
      guard let name = nameElement.flatMap(Self.preferredName) else {
        throw TrustedListError.malformed("no TSPName")
      }
      let elements =
        provider.child(TrustedListElement.namespace, TrustedListElement.tspServices)?
        .children(TrustedListElement.namespace, TrustedListElement.tspService) ?? []
      guard services.count + elements.count <= Self.maximumServices else {
        throw TrustedListError.bound(.services)
      }
      for service in elements {
        services.append(try Self.service(service, provider: name))
      }
    }
    return services
  }

  /// The certificates of every `ServiceDigitalIdentity/DigitalId/
  /// X509Certificate` under `parent`, at most `limit` of them, and how
  /// many did not parse as certificates and were left out.
  ///
  /// One that is not base64 is malformed; one that is base64 but not a
  /// certificate the platform reads (the national lists carry
  /// decades-old ones) is counted, since nothing can be anchored on it.
  private static func identity(
    under parent: XmlElement,
    limit: Int,
    bound: TrustedListError.Bound
  ) throws -> Identity {
    let elements = parent.descendants
      .filter { element in
        element.matches(TrustedListElement.namespace, TrustedListElement.digitalId)
      }
      .flatMap { element in
        element.children(TrustedListElement.namespace, TrustedListElement.x509Certificate)
      }
    guard elements.count <= limit else { throw TrustedListError.bound(bound) }
    var certificates: [Data] = []
    var unreadable = 0
    for element in elements {
      guard let der = XadesXmlParser.base64(element.text) else {
        throw TrustedListError.malformed("X509Certificate is not base64")
      }
      if CertificateFacts(der: der) != nil, SecCertificateCreateWithData(nil, der as CFData) != nil
      {
        certificates.append(der)
      } else {
        unreadable += 1
      }
    }
    return Identity(certificates: certificates, unreadable: unreadable)
  }

  /// One `OtherTSLPointer`.
  private static func pointer(_ pointer: XmlElement) throws -> TrustedListPointer {
    guard
      let identities = pointer.child(
        TrustedListElement.namespace, TrustedListElement.serviceDigitalIdentities)
    else {
      throw TrustedListError.malformed("pointer without ServiceDigitalIdentities")
    }
    let signers = try Self.identity(
      under: identities, limit: Self.maximumPointerSigners, bound: .pointerSigners)
    let location = try Self.requiredText(pointer, TrustedListElement.tslLocation)
    let information =
      pointer.child(TrustedListElement.namespace, TrustedListElement.additionalInformation)?
      .children(TrustedListElement.namespace, TrustedListElement.otherInformation)
      .flatMap(\.children) ?? []
    func find(_ namespace: String, _ localName: String) -> String? {
      information.first { element in element.matches(namespace, localName) }
        .map { element in XadesXmlParser.trimmed(element.text) }
    }
    guard let territory = find(TrustedListElement.namespace, TrustedListElement.schemeTerritory)
    else {
      throw TrustedListError.malformed("pointer without SchemeTerritory")
    }
    guard let kind = find(TrustedListElement.namespace, TrustedListElement.tslType) else {
      throw TrustedListError.malformed("pointer without TSLType")
    }
    let mediaType = find(TrustedListElement.additionalTypesNamespace, TrustedListElement.mimeType)
    return TrustedListPointer(
      location: Self.httpLocation(location),
      territory: territory,
      kind: Kind(uri: kind),
      format: mediaType == TrustedListElement.xmlMediaType ? .xml : .other,
      signers: signers.certificates,
      unreadableSigners: signers.unreadable
    )
  }

  /// `text` when it is an HTTP or HTTPS URL, else nil.
  private static func httpLocation(_ text: String) -> String? {
    guard
      let url = URL(string: text),
      let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      let host = url.host, !host.isEmpty
    else {
      return nil
    }
    return text
  }

  /// The type, status and status starting time of a
  /// `ServiceInformation` or `ServiceHistoryInstance`.
  private static func statusEntry(_ information: XmlElement) throws -> TrustService.StatusEntry {
    let kind = TrustService.Kind(
      uri: try Self.requiredText(information, TrustedListElement.serviceTypeIdentifier))
    guard
      let status = TrustService.Status(
        uri: try Self.requiredText(information, TrustedListElement.serviceStatus))
    else {
      throw TrustedListError.unknownServiceStatus
    }
    guard
      let since = XmlDateTime.instant(
        try Self.requiredText(information, TrustedListElement.statusStartingTime))
    else {
      throw TrustedListError.malformed("StatusStartingTime is not a dateTime")
    }
    return TrustService.StatusEntry(status: status, since: since, kind: kind)
  }

  /// One `TSPService` of the provider named `provider`.
  private static func service(_ service: XmlElement, provider: String) throws -> TrustService {
    guard
      let information = service.child(
        TrustedListElement.namespace, TrustedListElement.serviceInformation)
    else {
      throw TrustedListError.malformed("service without ServiceInformation")
    }
    let current = try Self.statusEntry(information)
    let nameElement = information.child(
      TrustedListElement.namespace, TrustedListElement.serviceName)
    guard let name = nameElement.flatMap(Self.preferredName) else {
      throw TrustedListError.malformed("service without ServiceName")
    }
    guard
      let identityElement = information.child(
        TrustedListElement.namespace, TrustedListElement.serviceDigitalIdentity)
    else {
      throw TrustedListError.malformed("service without ServiceDigitalIdentity")
    }
    let identity = try Self.identity(
      under: identityElement, limit: Self.maximumIdentityCertificates, bound: .identityCertificates)
    if identity.certificates.isEmpty, identity.unreadable == 0, current.kind.anchorRole != nil {
      throw TrustedListError.malformed("qualified service without a certificate")
    }
    let instances =
      service.child(TrustedListElement.namespace, TrustedListElement.serviceHistory)?
      .children(TrustedListElement.namespace, TrustedListElement.serviceHistoryInstance) ?? []
    guard instances.count <= Self.maximumHistory else { throw TrustedListError.bound(.history) }
    return TrustService(
      provider: provider,
      name: name,
      kind: current.kind,
      certificates: identity.certificates,
      unreadableCertificates: identity.unreadable,
      current: current,
      history: try instances.map(Self.statusEntry)
    )
  }
}
