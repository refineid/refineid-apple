// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import CryptoTokenKit
  import Foundation

  /// Reading the holder's handwritten signature off the card.
  ///
  /// This is the one operation that needs the card access number
  /// rather than a PIN: the signature lives in the travel-document
  /// application, and every file there is sealed until PACE has run.
  /// The number is asked for at the moment it is used and is not
  /// stored - it unlocks reading, so keeping it would be keeping a key
  /// to the holder's own card for no reason.
  ///
  /// Nothing here presents a PIN, so no retry counter is touched, and
  /// a wrong access number costs nothing but a refusal.
  extension CardMaintenance {
    /// Carries the non-Sendable card onto the background queue.
    private final class CarriedCard: @unchecked Sendable {
      let card: TKSmartCard

      init(_ card: TKSmartCard) {
        self.card = card
      }
    }

    /// The certificate identity used by a visible document stamp,
    /// optionally with the handwritten signature the card carries.
    internal struct Mark: Equatable, Sendable {
      /// The image, as the card stores it, or nil when this card has none.
      internal let bytes: Data?

      /// The exact qualified-signature certificate that states the identity.
      internal let certificate: Data

      /// The holder as a person reads it.
      internal let name: String

      /// The identifier the certificate states.
      internal let identifier: String
    }

    /// What reading the signature answered.
    internal enum SignatureOutcome: Equatable {
      /// No certificate identity could be read for a truthful stamp.
      case absent

      /// The card listed a handwritten signature but it could not be read.
      case imageUnreadable

      /// The certificate identity, optionally with the image the card stores.
      case mark(Mark)

      /// No card was readable.
      case noCard

      /// The access number was refused, or the secure channel could
      /// not be opened with it.
      case wrongAccessNumber
    }

    /// Reads the visible identity behind a PACE channel opened with `digits`.
    internal static func displayedSignature(
      accessNumber digits: String
    ) async -> SignatureOutcome {
      guard let number = CardAccessNumber(digits: digits) else {
        return .wrongAccessNumber
      }
      let answer = await Self.onTravelDocument(accessNumber: number) {
        operations in
        Self.displayedMark(from: operations)
      }
      return answer ?? .noCard
    }

    /// Reads the handwritten signature and the certificate identity.
    private static func displayedMark(
      from operations: CardOperations
    ) -> SignatureOutcome {
      // DG7 is read while the travel-document application is still
      // selected, behind the EF.COM inventory that makes the read safe.
      guard let inventory = try? operations.readDataGroupInventory() else {
        return .imageUnreadable
      }
      let image: DisplayedSignature.Image?
      do {
        image = try operations.readDisplayedSignature(listedBy: inventory)
      } catch {
        return .imageUnreadable
      }
      // Carry the exact certificate beside the visible identity. The
      // signing session later requires the same DER before spending PIN2.
      guard
        let certificate = (try? operations.readCertificate(.qualifiedSignature))
          ?? (try? operations.readCertificate(.secondQualifiedSignature)),
        let facts = CertificateFacts(der: certificate),
        let name = DistinguishedName.personalName(inName: facts.subjectName)
          ?? DistinguishedName.commonName(inName: facts.subjectName)
      else {
        return .absent
      }
      return .mark(
        Mark(
          bytes: image?.bytes,
          certificate: certificate,
          name: name,
          identifier: DistinguishedName.identifier(inName: facts.subjectName)
            ?? ""
        )
      )
    }

    /// Opens a session, runs PACE, selects the travel-document
    /// application, and hands the secure-messaged operations to
    /// `work`.
    ///
    /// PACE runs from the main file: an MSE:Set AT from inside an
    /// application context is answered 6985, so the main file is
    /// made current on the plain channel first.
    private static func onTravelDocument<Answer: Sendable>(
      accessNumber: CardAccessNumber,
      _ work: @escaping @Sendable (CardOperations) -> Answer?
    ) async -> Answer? {
      guard let manager = TKSmartCardSlotManager.default,
        let found = await CardSlotSearch.occupied(in: manager),
        let smartCard = found.slot.makeSmartCard()
      else {
        return nil
      }
      let carried = CarriedCard(smartCard)
      return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
          let answer = try? SmartCardChannel(carried.card).withSession {
            channel -> Answer? in
            try? CardOperations(channel: channel).selectMainFile()
            guard
              let keys = try? PaceEstablishment(channel: channel).establish(
                with: accessNumber
              )
            else {
              return nil
            }
            let operations = CardOperations(
              channel: SecureMessagingChannel(
                wrapping: channel, sessionKeys: keys
              )
            )
            guard
              (try? operations.selectTravelDocumentApplication()) != nil
            else {
              return nil
            }
            return work(operations)
          }
          continuation.resume(returning: answer.flatMap(\.self))
        }
      }
    }
  }

#endif
