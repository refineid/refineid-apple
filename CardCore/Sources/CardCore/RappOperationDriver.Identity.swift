// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation

  extension RappOperationDriver {
    /// The `read_identity` answer (RAPP v26.10.1 §9.1).
    public struct Identity: Sendable, Equatable {
      /// The cardholder's name.
      public let holderName: String
      /// The identifier the card's certificate names for its holder.
      public let cardID: String
      /// `YYYY-MM-DD`.
      public let issuanceDate: String
      /// `YYYY-MM-DD`.
      public let expirationDate: String
      /// DER certificates, at least one.
      public let certificates: [Data]

      /// Creates an identity answer.
      public init(
        holderName: String,
        cardID: String,
        issuanceDate: String,
        expirationDate: String,
        certificates: [Data]
      ) {
        self.holderName = holderName
        self.cardID = cardID
        self.issuanceDate = issuanceDate
        self.expirationDate = expirationDate
        self.certificates = certificates
      }

      /// The identity an authentication certificate states: the holder it
      /// names, the identifier its subject carries, and its validity window
      /// as the issuance and expiration dates.
      ///
      /// - Returns: nil when the certificate carries no readable validity.
      public init?(authenticationCertificate der: Data, holderName: String, cardID: String) {
        guard let window = CertificateValidity.window(inDer: der) else { return nil }
        self.init(
          holderName: holderName,
          cardID: cardID,
          issuanceDate: Self.calendarDate(window.notBefore),
          expirationDate: Self.calendarDate(window.notAfter),
          certificates: [der])
      }

      /// `YYYY-MM-DD` in UTC.
      private static func calendarDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
      }
    }
  }
#endif
