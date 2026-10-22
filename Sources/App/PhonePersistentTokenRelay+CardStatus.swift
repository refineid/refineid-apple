// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation
  import RappEngine
  import UIKit

  /// The custodian's word on its card (RAPP v26.10.22 §8.4).
  @MainActor
  extension PhonePersistentTokenRelay {
    /// What this phone knows of the reader card it serves.
    internal struct ReaderCard {
      /// The card's authentication certificate, once read; nil while no
      /// reader card is present.
      internal var certificate: Data?
      /// The preparation and certificate read under way, so a second
      /// request waits for it instead of queueing another read.
      internal var preparation: Task<Void, Never>?
      /// Changes whenever the reader card arrives or leaves, so a
      /// certificate read from an earlier card is never taken for the
      /// current one.
      internal var epoch = UUID()
    }

    /// Where the primed card's fingerprint is kept for the locked phone.
    private static let primedFingerprintKey = "fi.refineid.rapp.primed-card-fingerprint"

    /// The card the phone holds now, by the fingerprint of its
    /// authentication certificate; nil while it holds none, or one whose
    /// certificate it has not read yet.
    ///
    /// The reader card's certificate is held in memory. The primed card's
    /// lives in a keychain item that opens only while protected data is
    /// available, so while the phone is locked the primed card last read
    /// stands in for it (CC-70): a session that opens over Bluetooth from
    /// a pocket reports the card the holder can still present.
    internal var servedCardFingerprint: RappCertificateFingerprint? {
      if CardPresence.shared.isReaderCardPresent {
        return readerCard.certificate.flatMap(RappCertificateFingerprint.init(certificate:))
      }
      guard UIApplication.shared.isProtectedDataAvailable else {
        return primedFingerprintWhileLocked
      }
      let primed = (PrimeStore.storedIdentities().first?.certDER)
        .flatMap(RappCertificateFingerprint.init(certificate:))
      if primedFingerprintWhileLocked != primed {
        primedFingerprintWhileLocked = primed
      }
      return primed
    }

    /// The primed card's fingerprint as last read with protected data
    /// available, which stands in for it while the phone is locked.
    ///
    /// Kept in the app's defaults, which open after the first unlock, so it
    /// survives the relaunch iOS makes for a Bluetooth event while the phone
    /// stays locked (CC-70).
    private var primedFingerprintWhileLocked: RappCertificateFingerprint? {
      get {
        UserDefaults.standard.data(forKey: Self.primedFingerprintKey)
          .flatMap(RappCertificateFingerprint.init(stored:))
      }
      set {
        if let newValue {
          UserDefaults.standard.set(newValue.storedBytes, forKey: Self.primedFingerprintKey)
        } else {
          UserDefaults.standard.removeObject(forKey: Self.primedFingerprintKey)
        }
      }
    }

    /// Which card the phone holds (§8.4 items 1 and 2).
    ///
    /// Present while it holds one whose authentication certificate is known,
    /// so the requester can tell which card it is. An operation the card did
    /// not answer changes nothing here.
    internal var cardStatus: RappCardStatus {
      guard let fingerprint = servedCardFingerprint else { return .absent }
      return .present(fingerprint)
    }

    /// Tells every open session which card can answer, each one when it
    /// changed since that session was last told (§8.4 item 1).
    internal func reportCardStatus() {
      for session in sessions.values where session.isEstablished {
        reportCardStatus(to: session)
      }
    }

    /// Tells `session` which card can answer, when that changed since it
    /// was last told.
    internal func reportCardStatus(to session: ServedSession) {
      let status = cardStatus
      guard status != session.reportedCardStatus else { return }
      session.reportedCardStatus = status
      let coordinator = session.coordinator
      Task { try? await coordinator.reportCardStatus(status) }
    }

    /// A reader card or a prime arrived or left: every requester hears which
    /// card the phone holds now, and a PIN 1 held for another card ends
    /// (§11 item 2).
    internal func cardAvailabilityChanged() {
      readerCard.epoch = UUID()
      if !CardPresence.shared.isReaderCardPresent {
        readerCard.certificate = nil
      }
      HeldPin1.shared.keep(onlyFor: servedCardFingerprint)
      reportCardStatus()
      if CardPresence.shared.isReaderCardPresent {
        prepareReaderCard()
      } else {
        Task { await RappReaderSessionHolder.shared.cardLeft() }
      }
    }

    /// Opens the reader card's session and selects the application ahead
    /// of the first request while a requester is connected, and reads the
    /// card's authentication certificate once, so `card.status` can name
    /// the card.
    ///
    /// Both run on the reader holder's chain, between the card exchanges
    /// the operations make, and command no PIN; one preparation runs at a
    /// time, and a card that changed meanwhile is prepared once it is done.
    internal func prepareReaderCard() {
      guard !sessions.isEmpty, CardPresence.shared.isReaderCardPresent,
        readerCard.preparation == nil
      else { return }
      let epoch = readerCard.epoch
      readerCard.preparation = Task {
        await RappReaderSessionHolder.shared.prepare()
        if readerCard.certificate == nil {
          let outcome = await RappCardExecutor.readCertificate(
            cardAccessNumber: nil, signatureCertificate: false)
          if case .result(let certificate) = outcome {
            readerCertificateRead(certificate, epoch: epoch)
          }
        }
        readerCard.preparation = nil
        if epoch != readerCard.epoch {
          prepareReaderCard()
        }
      }
    }

    /// Takes the certificate read from the reader card present since
    /// `epoch`; one read from an earlier card is dropped.
    private func readerCertificateRead(_ certificate: Data, epoch: UUID) {
      guard epoch == readerCard.epoch, CardPresence.shared.isReaderCardPresent else { return }
      readerCard.certificate = certificate
      reportCardStatus()
    }
  }
#endif
