// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)
  import CardCore
  import Foundation
  import RappEngine

  extension PersistentTokenRegistry {
    /// Notified when a physical card in a reader is inserted or removed.
    ///
    /// The physical reader has absolute priority over RAPP remote tokens and connections.
    /// When a reader card is present:
    /// - All other identities (the remote RAPP token and any displaced configurations) are withdrawn.
    /// - Wireless connections to other devices (presence browsing, in-flight fetches) are put into passive state.
    /// - Remote tokens are suppressed from publishing.
    /// When the reader card leaves:
    /// - Presence watching resumes if pairings exist, allowing remote card discovery when no physical card is present.
    internal func readerCardPresenceChanged(isReaderCardPresent: Bool) {
      if isReaderCardPresent {
        Self.withdrawPublishedIdentity()
        _ = DriverConfiguredCredentials.dropDisplacedRemoteCardConfigurations()
        #if REFINEID_STREAM_TRANSPORT
          stopWatchingPresence()
        #endif
        #if DEBUG
          print(
            "[persistent-token] reader card present; remote identity withdrawn and wireless passive"
          )
          fflush(stdout)
        #endif
      } else {
        #if REFINEID_STREAM_TRANSPORT
          restartWatchingPresence()
        #else
          ensurePublished()
        #endif
      }
    }

    /// Writes the borrowed certificate again if this process still holds it.
    ///
    /// The physical reader has absolute priority. When a reader card is present,
    /// remote identities are withdrawn.
    internal func ensurePublished() {
      if CardPresence.shared.isReaderCardPresent {
        Self.withdrawPublishedIdentity()
        return
      }
      let hasPairs = (try? RappDeviceVault().activePairIDs().isEmpty == false) ?? false
      guard hasPairs else {
        Self.withdrawPublishedIdentity()
        return
      }
      #if REFINEID_STREAM_TRANSPORT
        guard holderIsAdvertising else { return }
      #endif
      if !Self.needsIdentity {
        seedHolderLine()
        return
      }
      guard let der = certificateDER ?? Self.publishedCertificateDER() else { return }
      Self.publish(certificateDER: der)
    }

    /// Fills the person line from a certificate this process already holds.
    internal func seedHolderLine() {
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
