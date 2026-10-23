// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)
  import CardCore
  import Foundation
  import RappEngine

  extension PersistentTokenRegistry {
    /// Notified when a physical card in a reader is inserted or removed.
    ///
    /// The physical reader has absolute priority over RAPP remote tokens and connections.
    /// A reader card suspends remote use while it is present (hierarchy
    /// specification §5.2, CC-102):
    /// - This computer withdraws: an open session with the phone closes
    ///   with `service_withdrawn` (RAPP v26.10.22 §4.5 item 8), the phone's
    ///   identity and any displaced configurations leave, and nothing
    ///   browses, scans or dials.
    /// - The switch and the pairings stay as they are; its watches stop.
    /// When the reader card leaves, remote use resumes as it was: with a
    /// pairing the phone is followed again without a code, and with none
    /// the code entry is offered again.
    internal func readerCardPresenceChanged(isReaderCardPresent: Bool) {
      #if os(macOS) && REFINEID_REMOTE_CARD
        RemoteUseSwitch.shared.suspend(isReaderCardPresent)
      #endif
      guard Self.dialsPhones else {
        Self.withdrawPublishedIdentity()
        return
      }
      if isReaderCardPresent {
        withdraw()
        _ = DriverConfiguredCredentials.dropDisplacedRemoteCardConfigurations()
        #if DEBUG
          print(
            "[persistent-token] reader card present; remote identity withdrawn and wireless passive"
          )
          fflush(stdout)
        #endif
      } else if Self.followsPhone {
        start()
      }
    }

    /// Writes the borrowed certificate again if this process still holds it.
    ///
    /// The physical reader has absolute priority. When a reader card is
    /// present, or remote use is off, remote identities are withdrawn.
    /// Nothing is written unless the phone's open session says a card is
    /// present, and an identity is offered only for the card that session
    /// names: one published for another card is withdrawn, to be read
    /// afresh (RAPP v26.10.22 §8.4 items 2 and 3).
    internal func ensurePublished() {
      guard Self.followsPhone else {
        Self.withdrawPublishedIdentity()
        return
      }
      if CardPresence.shared.isReaderCardPresent {
        Self.withdrawPublishedIdentity()
        return
      }
      let hasPairs = (try? RappDeviceVault().activePairIDs().isEmpty == false) ?? false
      guard hasPairs else {
        Self.withdrawPublishedIdentity()
        return
      }
      guard case .present(let named)? = holderCardStatus?.card else { return }
      if let published = Self.publishedCertificateDER(),
        RappCertificateFingerprint(certificate: published) != named
      {
        Self.withdrawPublishedIdentity()
        return
      }
      if !Self.needsIdentity {
        seedHolderLine()
        return
      }
      guard let der = certificateDER ?? Self.publishedCertificateDER(),
        RappCertificateFingerprint(certificate: der) == named
      else { return }
      Self.publish(der)
    }

    /// Fills the person line from a certificate this process already holds.
    internal func seedHolderLine() {
      guard Self.followsPhone else {
        Self.withdrawPublishedIdentity()
        return
      }
      let hasPairs = (try? RappDeviceVault().activePairIDs().isEmpty == false) ?? false
      guard hasPairs else {
        Self.withdrawPublishedIdentity()
        return
      }
      guard let der = certificateDER ?? Self.publishedCertificateDER() else { return }
      certificateDER = der
      if holderLine == nil {
        holderLine = DistinguishedName.holderLine(fromCertificate: der)
      }
    }
  }
#endif
