// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(MultipeerConnectivity) && canImport(RappEngine)
  import Foundation

  /// The authenticated payload a completed requester operation yields.
  public enum RappRequesterResponse: Sendable, Equatable {
    case authenticationCertificate(Data)
    case signature(Data)
    case signatureCertificate(Data)
  }
#endif
