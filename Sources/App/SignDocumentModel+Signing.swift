// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation

  /// Signing one document: in memory first, then to the place chosen.
  extension SignDocumentModel {
    /// Signs the pending document, then asks `choose` where it goes.
    ///
    /// The signature is finished in memory first, so the place it is
    /// offered under already carries its best signature time. A choice
    /// answered with nothing leaves nothing written.
    internal func sign(
      pin2: String,
      accessNumber: String,
      format: SignatureFormat,
      destination choose: DestinationChoice
    ) async {
      guard let source = pending, !working else { return }
      let appearance = beginSigning()
      defer { endSigning() }
      guard
        let finished = await signature(
          of: source,
          pin2: pin2,
          accessNumber: accessNumber,
          format: format,
          appearance: appearance
        )
      else { return }
      show(nil)
      _ = await save(
        finished,
        originals: [source],
        refusal: String(localized: "The signed document cannot replace the original."),
        choose: choose
      )
    }

    /// One document signed in memory; nil leaves the cause in `failure`.
    ///
    /// Internal, not private: a pile signs each of its documents here.
    internal func signature(
      of source: URL,
      pin2: String,
      accessNumber: String,
      format: SignatureFormat,
      appearance: Int
    ) async -> SignedDocument? {
      if DemoMode.shared.isActive {
        return await signWithVirtualCard(
          pin2: pin2, from: source, appearance: appearance
        )
      }
      do {
        switch format {
        case .asice:
          return try await signContainer([source], pin2: pin2)

        case .pades:
          return try await signPdf(source, pin2: pin2, accessNumber: accessNumber)
        }
      } catch {
        report(error, from: appearance)
        return nil
      }
    }
  }

#endif
