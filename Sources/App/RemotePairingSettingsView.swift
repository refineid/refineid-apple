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
          for: RappAutoPairingService.devicesDidChangeNotification
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
      let validRemoteDevices = remoteDevices.filter { $0.role == .holder }

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
        guard pair.role == .requester, !derivedRemotePairIDs.contains(pair.pairID),
          let pairName = RappPairNames.name(forPairID: pair.pairID)
        else {
          return false
        }
        return !validRemoteDevices.contains { remote in
          remote.deviceName.caseInsensitiveCompare(pairName) == .orderedSame
            || remote.modelName.caseInsensitiveCompare(pairName) == .orderedSame
        }
      }

      var seenExtraNames = Set<String>()
      var seenPairIDs = Set<Data>()
      let deduplicatedExtraPairs = validExtraPairs.filter { pair in
        guard seenPairIDs.insert(pair.pairID).inserted,
          let name = RappPairNames.name(forPairID: pair.pairID)
        else { return false }
        return seenExtraNames.insert(name.lowercased()).inserted
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
        let isOnline = isCurrentPair && PersistentTokenRegistry.shared.holderIsAdvertising
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
        guard let pairName = RappPairNames.name(forPairID: pair.pairID) else { continue }
        let idStr = pair.pairID.base64EncodedString()
        let isPreferred =
          idStr == effectivePreferredID
          || (model.selectedPairID == pair.pairID)

        let isCurrentPair = activePairID.map { pair.pairID == $0 } ?? isPreferred
        let isOnline = isCurrentPair && PersistentTokenRegistry.shared.holderIsAdvertising
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
          Text("No paired phones")
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
        Text("Paired phones")
      } footer: {
        HStack {
          Spacer()
          Button("Forget All", role: .destructive) {
            clearAll()
          }
          .buttonStyle(.borderless)
          .font(.caption)
          .foregroundStyle(.red)
        }
        .padding(.top, Layout.rowSpacing)
      }
    }

    private func clearAll() {
      preferredDeviceID = ""
      RappAutoPairingService.shared.clearAllRemoteDevices()
      model.revokeAll()
      CardCanOffer.storedSerials().forEach { CardCanOffer.forget(printedSerial: $0) }
      CardCanOffer.withdraw()
      _ = try? RappDeviceVault().deleteServiceNamespace()
      RappPairNames.forgetAll()
      PersistentTokenRegistry.withdrawPublishedIdentity()
      #if REFINEID_STREAM_TRANSPORT
        PersistentTokenRegistry.shared.stopWatchingPresence()
      #endif
      reload()
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
