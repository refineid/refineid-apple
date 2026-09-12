// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import XCTest

  /// The virtual card journeys every GUI test in this bundle drives.
  internal enum VirtualIDCardUITestSupport {
    internal enum Destination {
      case activation
      case cardAccessNumber
      case readerIdentity
      case registeredIdentity
    }

    internal struct CredentialJourney {
      internal let task: String
      internal let fields: [(identifier: String, value: String)]
      internal let action: String
      internal let outcome: String
    }
  }

#endif
