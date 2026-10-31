// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import Foundation

  /// Explicit development-only permission to retain a revoked signature.
  ///
  /// The normal collector must first authenticate a revoked status. Only that
  /// exact result may fall back to the already timestamped PAdES-B-T bytes.
  /// Release builds contain none of this type, argument, or behavior.
  internal enum DebugRevokedDocumentSigning {
    /// A normal-UI launch argument; it is deliberately not a debug launch mode.
    internal static let launchArgument = "--allow-revoked-signature-test"

    /// A signed reason that permanently identifies output from this mode.
    internal static let reason = "DEBUG revoked-certificate test"

    /// The warning shown before the card is asked to sign.
    internal static let armedWarning =
      "DEBUG test mode: an authenticated revoked document-signer certificate "
      + "may be saved as PAdES-B-T."

    /// The warning shown beside a file produced through the escape hatch.
    internal static let warning =
      "DEBUG test output: the signer certificate is revoked. The PDF contains "
      + "the card signature and its timestamp only (PAdES-B-T); it has no "
      + "LT/LTA evidence or document timestamp."

    /// Whether this process was explicitly launched with the escape hatch.
    internal static func isEnabled() -> Bool {
      Self.isEnabled(arguments: ProcessInfo.processInfo.arguments)
    }

    /// Whether the supplied process arguments explicitly enable this mode.
    internal static func isEnabled(arguments: [String]) -> Bool {
      arguments.contains(Self.launchArgument)
        && !DebugLaunchMode.allCases.contains { mode in
          arguments.contains(mode.rawValue)
        }
    }

    /// The timestamped result only when authenticated evidence says revoked.
    internal static func product(
      timestamped: DocumentSigner.TimestampedSignature,
      after error: Error,
      enabled: Bool
    ) -> DocumentSigner.Product? {
      guard
        enabled,
        let failure = error as? ValidationMaterialCollector.Failure,
        failure == .revoked(.documentSigner)
      else {
        return nil
      }
      return DocumentSigner.Product(
        bytes: timestamped.bytes,
        completion: .revokedSignerTest,
        signature: timestamped
      )
    }
  }

#endif
