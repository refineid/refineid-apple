// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The namespaces, element names and identifiers of ETSI TS 119 612
/// V2.3.1 the trusted-list reader consults.
internal enum TrustedListElement {
  /// The trusted-list namespace (annex B.0).
  internal static let namespace = "http://uri.etsi.org/02231/v2#"

  /// The namespace of the additional types, among them a pointer's
  /// `MimeType` (annex B.0).
  internal static let additionalTypesNamespace = "http://uri.etsi.org/02231/v2/additionaltypes#"

  /// The list type of the EU list of the lists (annex D.5.1).
  internal static let euListOfTheListsType =
    "http://uri.etsi.org/TrstSvc/TrustedList/TSLType/EUlistofthelists"

  /// The list type of an EU member state's list (annex D.5.1).
  internal static let euGenericType = "http://uri.etsi.org/TrstSvc/TrustedList/TSLType/EUgeneric"

  /// The qualified certificate-issuing service type (clause 5.5.1.1).
  internal static let qualifiedCertificatesType = "http://uri.etsi.org/TrstSvc/Svctype/CA/QC"

  /// The qualified time-stamping service type (clause 5.5.1.1).
  internal static let qualifiedTimeStampsType = "http://uri.etsi.org/TrstSvc/Svctype/TSA/QTST"

  /// The prefix every status identifier shares (annex D.5.6).
  internal static let statusPrefix = "http://uri.etsi.org/TrstSvc/TrustedList/Svcstatus/"

  /// The media type of a machine-processable list (clause 6.2).
  internal static let xmlMediaType = "application/vnd.etsi.tsl+xml"

  /// The language tag of English, the operator and service name
  /// preferred when a name comes in several languages (clause 5.1.4).
  internal static let english = "en"

  internal static let trustServiceStatusList = "TrustServiceStatusList"
  internal static let schemeInformation = "SchemeInformation"
  internal static let tslType = "TSLType"
  internal static let schemeOperatorName = "SchemeOperatorName"
  internal static let name = "Name"
  internal static let schemeTerritory = "SchemeTerritory"
  internal static let pointersToOtherTsl = "PointersToOtherTSL"
  internal static let otherTslPointer = "OtherTSLPointer"
  internal static let serviceDigitalIdentities = "ServiceDigitalIdentities"
  internal static let serviceDigitalIdentity = "ServiceDigitalIdentity"
  internal static let digitalId = "DigitalId"
  internal static let x509Certificate = "X509Certificate"
  internal static let tslLocation = "TSLLocation"
  internal static let additionalInformation = "AdditionalInformation"
  internal static let otherInformation = "OtherInformation"
  internal static let mimeType = "MimeType"
  internal static let listIssueDateTime = "ListIssueDateTime"
  internal static let nextUpdate = "NextUpdate"
  internal static let dateTime = "dateTime"
  internal static let trustServiceProviderList = "TrustServiceProviderList"
  internal static let trustServiceProvider = "TrustServiceProvider"
  internal static let tspInformation = "TSPInformation"
  internal static let tspName = "TSPName"
  internal static let tspServices = "TSPServices"
  internal static let tspService = "TSPService"
  internal static let serviceInformation = "ServiceInformation"
  internal static let serviceTypeIdentifier = "ServiceTypeIdentifier"
  internal static let serviceName = "ServiceName"
  internal static let serviceStatus = "ServiceStatus"
  internal static let statusStartingTime = "StatusStartingTime"
  internal static let serviceHistory = "ServiceHistory"
  internal static let serviceHistoryInstance = "ServiceHistoryInstance"
}
