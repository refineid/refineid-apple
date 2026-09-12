// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import SwiftUI

  /// The Settings pane showing what this device remembers in the keychain.
  ///
  /// Card serials and pairing identifiers are printed on the hardware or
  /// identify it, so they are safe to list. Digits and secrets are never
  /// displayed; each row only forgets them.
  internal struct StoredDataSettingsView: View {
    @State private var serials: [String] = []
    @State private var pairIDs: [Data] = []
    @State private var showsEraseConfirmation = false
    @State private var eraseResult: String?

    internal var body: some View {
      Form {
        cardNumbersSection
        pairingsSection
        eraseSection
      }
      .formStyle(.grouped)
      .onAppear(perform: reload)
      .alert(
        "Erase all RefineID keychain data?",
        isPresented: $showsEraseConfirmation
      ) {
        Button("Erase everything", role: .destructive) {
          erase()
        }
        Button("Cancel", role: .cancel) {
          // Dismisses the confirmation with nothing erased.
        }
      } message: {
        Text(
          "Cards will ask for their numbers again and devices will need re-pairing."
        )
      }
    }

    private var cardNumbersSection: some View {
      Section("Card numbers") {
        if serials.isEmpty {
          Text("No stored card numbers.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(serials, id: \.self) { serial in
            HStack {
              Text(serial.uppercased())
              Spacer()
              Button("Delete", role: .destructive) {
                CardCanOffer.forget(printedSerial: serial)
                reload()
              }
            }
          }
        }
      }
    }

    private var pairingsSection: some View {
      Section("Pairings") {
        if pairIDs.isEmpty {
          Text("No pairings.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(pairIDs, id: \.self) { pairID in
            Text(
              RappPairNames.name(forPairID: pairID)
                ?? pairID.map { String(format: "%02x", $0) }.joined())
          }
        }
      }
    }

    private var eraseSection: some View {
      Section("Erase everything") {
        Text(
          "Deletes every card number, pairing, and credential RefineID keeps in the keychain."
        )
        .foregroundStyle(.secondary)
        Button("Erase all RefineID keychain data", role: .destructive) {
          showsEraseConfirmation = true
        }
        if let eraseResult {
          Text(eraseResult)
            .foregroundStyle(.secondary)
        }
      }
    }

    private func reload() {
      serials = CardCanOffer.storedSerials()
      pairIDs = (try? RappDeviceVault().activePairIDs()) ?? []
    }

    private func erase() {
      do {
        let deleted = try RappDeviceVault().deleteServiceNamespace()
        eraseResult = "Erased \(deleted) keychain items."
      } catch {
        eraseResult = "Erase failed: \(error.localizedDescription)"
      }
      reload()
    }
  }

#endif
