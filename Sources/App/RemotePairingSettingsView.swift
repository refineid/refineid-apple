// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import RappEngine
  import SwiftUI

  /// The Settings pane for managing paired devices and automatic connections.
  internal struct RemotePairingSettingsView: View {
    private enum Layout {
      static let rowSpacing: CGFloat = 6
      static let refreshIntervalSeconds: TimeInterval = 3
      static let idPrefixBytes = 4
    }

    private struct DisplayedDevice {
      let identifier: String
      let name: String
      let modelName: String?
      let isPreferred: Bool
      let isOnline: Bool
      let isConnected: Bool
      let onDelete: () -> Void
      let onSetPreferred: () -> Void
    }

    @AppStorage("fi.refineid.preferredRemoteDeviceID")
    private var preferredDeviceID: String = ""

    @StateObject private var model = RappPairingModel()
    @State private var remoteDevices: [RappCloudDeviceRecord] = []

    internal var body: some View {
      Form {
        remoteDevicesSection
      }
      .formStyle(.grouped)
      .onAppear {
        reload()
        RappAutoPairingService.shared.reconcile()
      }
      .onReceive(
        NotificationCenter.default.publisher(
          for: RappAutoPairingService.pairingsDidChangeNotification
        )
      ) { _ in
        reload()
      }
      .onReceive(
        NotificationCenter.default.publisher(
          for: RappPairingModel.pairingsDidChangeNotification
        )
      ) { _ in
        reload()
      }
      .onReceive(
        NotificationCenter.default.publisher(
          for: NSApplication.didBecomeActiveNotification
        )
      ) { _ in
        reload()
      }
      .onReceive(
        Timer.publish(every: Layout.refreshIntervalSeconds, on: .main, in: .common).autoconnect()
      ) { _ in
        reload()
      }
    }

    private var displayedDevices: [DisplayedDevice] {
      let validRemoteDevices = remoteDevices.filter { device in
        device.role == .holder
      }

      let localPublicKey = RappAutoPairingService.shared.localIdentity?.publicKeyData

      let derivedRemotePairIDs: Set<Data> = Set(
        validRemoteDevices.compactMap { device in
          guard let localPublicKey else { return nil }
          return RappSameAccountPairBuilder.derivePairIdentifier(
            publicKeyA: localPublicKey,
            publicKeyB: device.staticPublicKey
          )
        }
      )

      let validExtraPairs = model.pairs.filter { pair in
        guard pair.role == .requester else { return false }
        guard !derivedRemotePairIDs.contains(pair.pairID) else { return false }
        let pairName = RappPairNames.name(forPairID: pair.pairID) ?? ""
        guard !pairName.isEmpty else { return true }
        return !validRemoteDevices.contains { remote in
          remote.deviceName.caseInsensitiveCompare(pairName) == .orderedSame
            || remote.modelName.caseInsensitiveCompare(pairName) == .orderedSame
        }
      }

      var seenExtraNames = Set<String>()
      var seenPairIDs = Set<Data>()
      let deduplicatedExtraPairs = validExtraPairs.filter { pair in
        guard seenPairIDs.insert(pair.pairID).inserted else { return false }
        let name = (RappPairNames.name(forPairID: pair.pairID) ?? "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .lowercased()
        guard !name.isEmpty else { return true }
        return seenExtraNames.insert(name).inserted
      }

      let totalCount = validRemoteDevices.count + deduplicatedExtraPairs.count
      let effectivePreferredID =
        preferredDeviceID.isEmpty && totalCount == 1
        ? (validRemoteDevices.first?.deviceID.uuidString
          ?? deduplicatedExtraPairs.first?.pairID.base64EncodedString() ?? "")
        : preferredDeviceID

      let activePairID = PersistentTokenRegistry.activePairID

      var list: [DisplayedDevice] = []

      for device in validRemoteDevices {
        let idStr = device.deviceID.uuidString
        let isPreferred = idStr == effectivePreferredID

        let derivedPairID = localPublicKey.flatMap { publicKey in
          RappSameAccountPairBuilder.derivePairIdentifier(
            publicKeyA: publicKey,
            publicKeyB: device.staticPublicKey
          )
        }
        let isCurrentPair =
          (derivedPairID != nil && activePairID != nil)
          ? (derivedPairID == activePairID) : isPreferred
        let isOnline =
          RappAutoPairingService.shared.isDeviceOnline(
            deviceID: device.deviceID,
            deviceName: device.deviceName
          ) || (isCurrentPair && PersistentTokenRegistry.shared.holderIsAdvertising)
        let isConnected = isPairConnected(isCurrent: isCurrentPair, isOnline: isOnline)

        list.append(
          DisplayedDevice(
            identifier: idStr,
            name: device.deviceName,
            modelName: device.modelName,
            isPreferred: isPreferred,
            isOnline: isOnline,
            isConnected: isConnected,
            onDelete: {
              if isPreferred { preferredDeviceID = "" }
              RappAutoPairingService.shared.removeRemoteDevice(deviceID: device.deviceID)
              if let derivedPairID {
                model.revoke(pairID: derivedPairID)
              }
              reload()
            },
            onSetPreferred: {
              preferredDeviceID = idStr
              if let derivedPairID {
                model.select(pairID: derivedPairID)
              }
              PersistentTokenRegistry.shared.restartWatchingPresence()
            }
          )
        )
      }

      for pair in deduplicatedExtraPairs {
        let idStr = pair.pairID.base64EncodedString()
        let rawName = RappPairNames.name(forPairID: pair.pairID)?
          .trimmingCharacters(in: .whitespacesAndNewlines)
        let pairName: String
        if let rawName, !rawName.isEmpty {
          pairName = rawName
        } else {
          let hexShort = pair.pairID.prefix(Layout.idPrefixBytes)
            .map { String(format: "%02x", $0) }
            .joined()
          pairName = String(localized: "Remote Device (\(hexShort)…)")
        }
        let isPreferred =
          idStr == effectivePreferredID
          || (model.selectedPairID == pair.pairID)

        let isCurrentPair = activePairID.map { pair.pairID == $0 } ?? isPreferred
        let isOnline =
          RappAutoPairingService.shared.isDeviceOnline(
            deviceID: nil,
            deviceName: pairName
          ) || (isCurrentPair && PersistentTokenRegistry.shared.holderIsAdvertising)
        let isConnected = isPairConnected(isCurrent: isCurrentPair, isOnline: isOnline)

        list.append(
          DisplayedDevice(
            identifier: idStr,
            name: pairName,
            modelName: nil,
            isPreferred: isPreferred,
            isOnline: isOnline,
            isConnected: isConnected,
            onDelete: {
              if isPreferred { preferredDeviceID = "" }
              model.revoke(pairID: pair.pairID)
              for remote in validRemoteDevices
              where remote.deviceName.caseInsensitiveCompare(pairName) == .orderedSame {
                RappAutoPairingService.shared.removeRemoteDevice(deviceID: remote.deviceID)
              }
              reload()
            },
            onSetPreferred: {
              preferredDeviceID = idStr
              model.select(pairID: pair.pairID)
              PersistentTokenRegistry.shared.restartWatchingPresence()
            }
          )
        )
      }

      return list.sorted { lhs, rhs in
        if lhs.isPreferred != rhs.isPreferred { return lhs.isPreferred }
        if lhs.isConnected != rhs.isConnected { return lhs.isConnected }
        if lhs.isOnline != rhs.isOnline { return lhs.isOnline }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
      }
    }

    private var remoteDevicesSection: some View {
      let devices = displayedDevices
      return Section {
        if devices.isEmpty {
          Text("Ei liitettyjä laitteita")
            .foregroundStyle(.secondary)
        } else {
          ForEach(devices, id: \.identifier) { device in
            RemoteDeviceRow(
              name: device.name,
              modelName: device.modelName,
              isOnline: device.isOnline,
              isConnected: device.isConnected,
              onDelete: device.onDelete
            )
          }
        }
      } header: {
        Text("Etälaitteet")
      } footer: {
        if !devices.isEmpty {
          HStack {
            Spacer()
            Button("Poista kaikki etälaitteet", role: .destructive) {
              preferredDeviceID = ""
              RappAutoPairingService.shared.clearAllRemoteDevices()
              model.revokeAll()
              PersistentTokenRegistry.withdrawPublishedIdentity()
              #if REFINEID_STREAM_TRANSPORT
                PersistentTokenRegistry.shared.stopWatchingPresence()
              #endif
              reload()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.red)
          }
          .padding(.top, Layout.rowSpacing)
        }
      }
    }

    private func reload() {
      model.refresh()
      remoteDevices = RappAutoPairingService.shared.remoteDevices
    }

    private func isPairConnected(isCurrent: Bool, isOnline: Bool) -> Bool {
      isCurrent && isOnline && PersistentTokenRegistry.shared.holderIsAdvertising
        && PersistentTokenRegistry.shared.certificateDER != nil
    }
  }

#endif
