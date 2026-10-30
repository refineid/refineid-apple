// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) || os(macOS)
  import CardCore

  internal enum RappAuthorizationDecision: Sendable, CustomReflectable {
    case approvedBrowserAuthentication(pin1: Pin1Entry)
    case approvedDocumentSignature(pin2: Pin2Entry)
    case denied

    /// High-level name of the decision suitable for tracing without logging credentials.
    internal var summary: String {
      switch self {
      case .approvedBrowserAuthentication:
        return "approvedBrowserAuthentication"
      case .approvedDocumentSignature:
        return "approvedDocumentSignature"
      case .denied:
        return "denied"
      }
    }

    internal var customMirror: Mirror {
      Mirror(self, children: ["decision": summary])
    }
  }
#endif
