// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import os.log
  import SwiftUI

  /// Who the card says they are, or what to do about it.
  ///
  /// A card mints in well under a second, and for that moment it is
  /// present without an identity yet published. That is not a fault and
  /// must not be shouted as one: the row shows nothing while it settles
  /// and only warns once the state has lasted long enough to mean
  /// something. A card in this Mac's reader overrides the paired phone and
  /// carries the control that opens its PIN codes. With remote use off the
  /// row asks for a reader or its card. A paired phone's line says it is
  /// connecting until the phone offers an identity, then names the holder
  /// and the phone, and asks for the card when the phone's card reader is
  /// empty.
  internal struct IdentityStateView: View {
    /// One tracked event.
    ///
    /// Token-list movement matters only while an identity is published,
    /// because only then is there a holder name to re-read.
    private enum TrackKey: Equatable {
      case availability(LoginIdentityModel.Availability)
      case ready(generation: Int, borrowed: String?)
      case demo(revision: Int, cardPresent: Bool)
    }

    #if DEBUG
      /// Row outcomes, in development builds only.
      ///
      /// States, never a name. A production build writes no
      /// diagnostics.
      private static let log = Logger(
        subsystem: "fi.refineid.ReFineID", category: "identity-row"
      )
    #endif

    /// What the login row keys on.
    internal let availability: LoginIdentityModel.Availability

    /// A completed activation check and recovery found no usable
    /// identity.
    ///
    /// Until that event, absence means that the card is still being
    /// read rather than that it failed.
    internal let warnsUnavailableCard: Bool

    /// The model, watched so a token event re-reads the name even
    /// when the availability itself did not move.
    private let model = LoginIdentityModel.shared

    /// The reader and its card, observed so the line follows a reader
    /// being attached or removed.
    @ObservedObject private var cardPresence = CardPresence.shared

    /// The cards in this Mac's readers and the one the holder chose.
    private let selection = CardSelection.shared

    /// Who the card says they are, read when a card is ready.
    ///
    /// Held here rather than in the model because it is worth nothing
    /// once the card is gone, and the row is the only thing that shows
    /// it.
    @State private var holder: String?

    /// The person line the remote-card registry already holds.
    ///
    /// Used when the keychain has not yet listed the borrowed token
    /// the registry just published.
    private var borrowedHolderLine: String? {
      PersistentTokenRegistry.shared.holderLine
    }

    /// The event which can change the row's asynchronous contents.
    private var trackKey: TrackKey {
      if DemoMode.shared.isActive {
        return .demo(
          revision: DemoMode.shared.revision,
          cardPresent: DemoMode.shared.state.card.cardPresent
        )
      }
      switch availability {
      case .ready:
        return .ready(generation: model.generation, borrowed: borrowedHolderLine)

      case .cardWithoutIdentity, .noCard:
        return .availability(availability)
      }
    }

    internal var body: some View {
      content
        .task(id: trackKey) {
          await track()
        }
    }

    /// Whether the holder has remote use on.
    private var remoteUse: Bool {
      #if REFINEID_REMOTE_CARD
        RemoteUseSwitch.shared.isOn
      #else
        false
      #endif
    }

    /// Whether the platform denies this app the local network: the
    /// remote-use switch's browse or a dial to a phone was refused it.
    private var localNetworkDenied: Bool {
      #if REFINEID_REMOTE_CARD
        PersistentTokenRegistry.shared.localNetworkDenied
          || RemoteUseSwitch.shared.blockage == .localNetworkNotAllowed
      #else
        false
      #endif
    }

    /// What the row knows now.
    ///
    /// A demonstration's card sits in a virtual reader, and no phone is
    /// paired with it unless a development launch shows one
    /// (``DemoPairedPhone``).
    private var facts: RequesterFacts {
      if DemoMode.shared.isActive {
        #if DEBUG
          if DemoPairedPhone.isShown {
            return DemoPairedPhone.facts(availability: availability)
          }
        #endif
        let card = DemoMode.shared.state.card
        return RequesterFacts(
          availability: availability,
          warnsUnavailableCard: warnsUnavailableCard,
          readerConnected: card.readerConnected,
          cardPresent: card.cardPresent,
          remoteUse: remoteUse,
          phonePaired: false,
          phoneThatForgot: nil,
          phoneJustPaired: nil,
          localNetworkDenied: false,
          phoneCardStatus: nil
        )
      }
      let registry = PersistentTokenRegistry.shared
      return RequesterFacts(
        availability: availability,
        warnsUnavailableCard: warnsUnavailableCard,
        readerConnected: cardPresence.isReaderConnected,
        cardPresent: cardPresence.isCardPresent,
        remoteUse: remoteUse,
        phonePaired: registry.pairedPhoneID != nil,
        phoneThatForgot: registry.phoneThatForgot,
        phoneJustPaired: registry.phoneJustPaired,
        localNetworkDenied: localNetworkDenied,
        phoneCardStatus: registry.holderCardStatus
      )
    }

    private var readingLine: some View {
      Text("Reading information…")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var content: some View {
      switch IdentityLine.derive(facts) {
      case .reading:
        readingLine

      case .localHolder:
        // Who is about to sign: someone with two cards can see which
        // one is in the reader before spending a PIN on it. Until the
        // name is read the line names no one - a claim without the
        // name behind it is not worth showing.
        // With two or more cards the lines are the choice of the card
        // to use.
        if selection.cards.count > 1 {
          CardChoiceList(selection: selection)
        } else if let line = selection.cards.first?.holderLine ?? holder {
          Text(line)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          readingLine
        }

      case .connectingToPairedPhone(let phone):
        HStack {
          ProgressView()
            .controlSize(.small)
          Text("Connecting to \(phone)…")
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

      case .cardNotReady:
        Text("Remove the card from the reader for a moment.")
          .foregroundStyle(.orange)
          .frame(maxWidth: .infinity, alignment: .leading)

      case .connectReader:
        Text("Connect a card reader.")
          .foregroundStyle(.secondary)

      case .insertCard:
        Text("Insert the card into the reader.")
          .foregroundStyle(.secondary)

      case .paired(let lead):
        PairedPhoneLine(lead: lead, holder: holder ?? borrowedHolderLine)

      case .phoneForgot(let phone):
        Text("\(phone) forgot this computer.")
          .foregroundStyle(.secondary)

      case .pairPhone:
        RemotePairingPromptView()

      case .localNetworkDenied:
        LocalNetworkNotice(message: LocalNetworkSettings.deniedMessage)
      }
    }

    /// Follows one availability and reads the name when ready.
    ///
    /// The holder's name is read off the main actor and never blocks
    /// the row.
    private func track() async {
      #if DEBUG
        Self.log.info("track: \(String(describing: self.availability))")
      #endif
      switch availability {
      case .ready:
        if DemoMode.shared.isActive {
          selection.show([])
          holder = DemoMode.shared.state.card.cardPresent ? DemoMode.shared.holderName : nil
          return
        }
        let tokenIDs = Array(model.ownedTokenIDs)
        await selection.reload(tokenIDs: tokenIDs) { tokenID in
          model.slotName(ofTokenID: tokenID)
        }
        if let borrowed = borrowedHolderLine {
          holder = borrowed
          return
        }
        guard selection.cards.isEmpty else {
          holder = selection.cards.first?.holderLine
          return
        }
        holder = await Task.detached(priority: .utility) {
          PublishedIdentityName.current(tokenIDs: tokenIDs)
        }.value

      case .cardWithoutIdentity, .noCard:
        selection.show([])
        holder = nil
      }
    }
  }

#endif
