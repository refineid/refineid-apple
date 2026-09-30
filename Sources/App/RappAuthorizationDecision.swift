// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) || os(macOS)
  internal enum RappAuthorizationDecision: Sendable, Equatable, CustomReflectable {
    case approved
    case approvedBrowserAuthentication(pin1: Pin1AuthorizationDigits)
    case approvedDocumentSignature(pin2: Pin2AuthorizationDigits)
    case denied

    /// High-level name of the decision suitable for tracing without logging credentials.
    internal var summary: String {
      switch self {
      case .approved:
        return "approved"
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
