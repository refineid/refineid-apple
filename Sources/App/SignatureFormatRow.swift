// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The signature-shape row: a choice when every document could take
  /// either shape, the same control locked otherwise.
  ///
  /// ASiC-E is the container format Estonian DigiDoc and other
  /// European tooling exchanges; a PDF can instead carry the signature
  /// inside itself, which is the default because the output stays an
  /// ordinary PDF.
  ///
  /// The choice is judged over the whole pile rather than the document
  /// whose name shows. One file of another type among PDFs takes the
  /// choice away - nothing but a PDF has an inside to sign - and then
  /// the picker is disabled rather than replaced by a label: a control
  /// that vanishes when a file is added looks like a lost feature, and
  /// a disabled one says the file is what locked it. Removing that
  /// file visibly unlocks the same control.
  internal struct SignatureFormatRow: View {
    /// Every file waiting to be signed.
    internal let documents: [URL]

    /// The chosen shape.
    @Binding internal var format: SignatureFormat

    /// Whether the signature could go inside each document as it is.
    private var everyOneAPdf: Bool {
      !documents.isEmpty && documents.allSatisfy(SignatureFormat.isPdf)
    }

    internal var body: some View {
      // The shapes: PDF (PAdES) or Container (ASiC-E).
      Picker("Format", selection: $format) {
        Text("PDF")
          .tag(SignatureFormat.pades)
        Text("Container").tag(SignatureFormat.asice)
      }
      .disabled(!everyOneAPdf)
      .accessibilityIdentifier("signatureFormat")
    }
  }

#endif
