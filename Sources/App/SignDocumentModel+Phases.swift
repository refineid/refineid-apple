// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation

  /// The signing steps, as the window shows them.
  extension SignDocumentModel {
    /// The observer is built outside the main actor: it is called from
    /// whatever task the signature runs on.
    nonisolated private static func phaseObserver(
      for model: SignDocumentModel
    ) -> @Sendable (DocumentSigningPhase) -> Void {
      { [weak model] step in
        Task { @MainActor in model?.show(step) }
      }
    }

    /// Runs `work` with each signing step shown as it begins.
    internal func reportingPhases<T: Sendable>(
      _ work: () async throws -> T
    ) async rethrows -> T {
      try await DocumentSigner.$phaseObserver.withValue(
        Self.phaseObserver(for: self)
      ) {
        try await work()
      }
    }
  }

#endif
