// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) || os(macOS)

  import CardCore
  import SwiftUI

  /// The virtual card stored CANs, stored state toggles, and signing-request switch.
  internal struct VirtualIDCardDeviceSection: View {
    @Binding internal var draft: VirtualIDCard.Snapshot

    internal var body: some View {
      Section(
        virtualCardLocalized("section.deviceState", defaultValue: "Device state")
      ) {
        deviceCanFields
        deviceStoredToggles
        deviceSigningButton
      }
    }

    @ViewBuilder private var deviceCanFields: some View {
      if DemoMode.offersNearField {
        TextField(
          virtualCardLocalized(
            "device.storedCan",
            defaultValue: "Stored CAN"),
          text: optionalBinding(\.storedCardAccessNumber),
          axis: .vertical
        )
        #if os(iOS)
          .keyboardType(.numberPad)
        #endif
        .virtualCardEditorField()
        .accessibilityIdentifier("virtualCardStoredCAN")
        TextField(
          virtualCardLocalized(
            "device.connectedCan",
            defaultValue: "Connected CAN"),
          text: optionalBinding(\.connectedCardAccessNumber),
          axis: .vertical
        )
        #if os(iOS)
          .keyboardType(.numberPad)
        #endif
        .virtualCardEditorField()
        .accessibilityIdentifier("virtualCardConnectedCAN")
      }
    }

    @ViewBuilder private var deviceStoredToggles: some View {
      Toggle(
        virtualCardLocalized(
          "device.identityCached",
          defaultValue: "Identity cached"),
        isOn: $draft.device.cachedIdentity
      )
      .accessibilityIdentifier("virtualCardIdentityCached")
      Toggle(
        virtualCardLocalized(
          "device.tokenRegistered",
          defaultValue: "Token registered"),
        isOn: $draft.device.tokenRegistered
      )
      .accessibilityIdentifier("virtualCardTokenRegistered")
    }

    @ViewBuilder private var deviceSigningButton: some View {
      Button {
        draft.device.pendingSigningRequest.toggle()
      } label: {
        LabeledContent(
          virtualCardLocalized(
            "device.signingPending",
            defaultValue: "Signing request pending")
        ) {
          Image(
            systemName: draft.device.pendingSigningRequest
              ? "checkmark.circle.fill"
              : "circle")
        }
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("virtualCardSigningPending")
      .accessibilityValue(
        Text(
          virtualCardLocalized(
            draft.device.pendingSigningRequest
              ? "state.enabled"
              : "state.disabled",
            defaultValue: draft.device.pendingSigningRequest
              ? "Enabled"
              : "Disabled")))
    }

    private func optionalBinding(
      _ keyPath: WritableKeyPath<VirtualIDCard.DeviceState, String?>
    ) -> Binding<String> {
      Binding(
        get: { draft.device[keyPath: keyPath] ?? "" },
        set: { entered in
          draft.device[keyPath: keyPath] = entered.isEmpty ? nil : entered
        })
    }
  }

#endif
