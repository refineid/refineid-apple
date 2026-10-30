// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) || os(macOS)

  import CardCore
  import SwiftUI

  /// The virtual card holder identity fields.
  internal struct VirtualIDCardIdentitySection: View {
    @Binding internal var draft: VirtualIDCard.Snapshot

    internal var body: some View {
      identityContent
    }

    @ViewBuilder private var identityContent: some View {
      Section(
        virtualCardLocalized("section.identity", defaultValue: "Identity")
      ) {
        TextField(
          virtualCardLocalized("identity.name", defaultValue: "Name"),
          text: $draft.card.holderName,
          axis: .vertical
        )
        .virtualCardEditorField()
        .accessibilityIdentifier("virtualCardName")
        TextField(
          virtualCardLocalized(
            "identity.electronicClientIdentifier",
            defaultValue: "Electronic client identifier"),
          text: $draft.card.electronicClientIdentifier,
          axis: .vertical
        )
        .virtualCardEditorField()
        .accessibilityIdentifier("virtualCardElectronicIdentifier")
        TextField(
          virtualCardLocalized(
            "identity.chipSerial",
            defaultValue: "Chip serial"),
          text: chipSerialText,
          axis: .vertical
        )
        .virtualCardEditorField()
        .accessibilityIdentifier("virtualCardChipSerial")
      }
    }

    /// The chip serial as editable text; only a valid serial is kept.
    private var chipSerialText: Binding<String> {
      Binding(
        get: { draft.card.chipSerial.value },
        set: { text in
          if let serial = ChipSerial(value: text) {
            draft.card.chipSerial = serial
          }
        })
    }
  }

#endif
