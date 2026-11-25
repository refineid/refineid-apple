// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation

  /// Localized prompt titles, origins, and error constants for
  /// ``WebEidCoordinator``.
  extension WebEidCoordinator {
    internal static let cancelledError = WebEidError(
      code: .userCancelled,
      message: "User cancelled the Web eID request"
    )

    internal static let timeoutError = WebEidError(
      code: .userTimeout,
      message: "Web eID user interaction timed out"
    )

    internal static func originText(for command: WebEidCommand) -> String {
      switch command {
      case .authenticate(let origin, _, _), .getSigningCertificate(let origin, _):
        origin.value

      case .sign(let request):
        request.origin.value

      case .status:
        ""
      }
    }

    internal static func requiredRole(for command: WebEidCommand) -> CredentialRole? {
      switch command {
      case .authenticate:
        .pin1

      case .sign:
        .pin2

      case .status, .getSigningCertificate:
        nil
      }
    }

    internal static func dialogTitle(for command: WebEidCommand) -> String {
      switch command {
      case .authenticate:
        String(localized: "Website Login")

      case .getSigningCertificate:
        String(localized: "Share Signing Certificate")

      case .sign:
        String(localized: "Sign Document")

      case .status:
        String(localized: "RefineID")
      }
    }

    internal static func confirmTitle(for command: WebEidCommand) -> String {
      switch command {
      case .authenticate:
        String(localized: "Log in")

      case .getSigningCertificate, .status:
        String(localized: "Confirm")

      case .sign:
        String(localized: "Sign")
      }
    }
  }

#endif
