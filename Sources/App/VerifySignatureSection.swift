// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// The facts of one signature in a verification report: the signer,
/// the issuer, every check, the times and the level reached.
///
/// The signer's name appears here and nowhere else.
internal struct VerifySignatureSection: View {
  private static var header: some View {
    Text(VerifyText.text("verify.signature", "Signature"))
      .frame(maxWidth: .infinity, alignment: .leading)
      .listRowInsets(EdgeInsets())
  }

  internal let entry: DocumentVerification.SignatureEntry

  /// Whether the live revocation check is still running.
  internal let checking: Bool

  internal var body: some View {
    switch entry {
    case .judged(let report):
      judged(report)

    case .unsupported:
      Section {
        VerifyDocumentRow(indicator: .fails) {
          PersonRowLabel(configured: false)
        } value: {
          Text(
            VerifyText.text("verify.errorUnsupported", "The signature profile is not supported."))
        }
      } header: {
        Self.header
      }
    }
  }

  /// The commonName of the CA that issued the signer, as the signer
  /// certificate names it, cleaned as the signer's name is.
  private static func issuer(of report: DocumentVerification.SignatureReport) -> String? {
    guard
      let facts = CertificateFacts(der: report.signerCertificate),
      let name = DistinguishedName.commonName(inName: facts.issuerName)
    else {
      return nil
    }
    return DisplayedSignerName.text(of: name)
  }

  /// One fact row: its name, the value line under it when there is
  /// one, and the indicator column.
  private static func row(_ name: String, _ value: VerifyDocumentRowValue) -> some View {
    VerifyDocumentRow(indicator: value.indicator) {
      Text(name)
    } value: {
      if let line = value.line {
        Text(line)
          .accessibilityLabel(Text(verbatim: value.accessibilityLine))
      }
    }
  }

  private static func row(_ name: String, holds: Bool) -> some View {
    Self.row(name, VerifyDocumentRowValue(indicator: holds ? .holds : .fails))
  }

  /// The timestamp row of one signature: the best signature time,
  /// which is the earliest anchored time, a claimed time marked
  /// unproven, a failed token, or none.
  private static func timestampValue(
    of report: DocumentVerification.SignatureReport
  ) -> VerifyDocumentRowValue {
    if let proven = report.proofOfExistence {
      return VerifyDocumentRowValue(text: VerifyText.formatted(proven), indicator: .holds)
    }
    if let claimed = report.claimedTime {
      return Self.unprovenValue(claimed)
    }
    if report.hasInvalidTimestamp {
      return VerifyDocumentRowValue(indicator: .fails)
    }
    return VerifyDocumentRowValue(secondaryText: VerifyText.text("verify.timestampNone", "None"))
  }

  /// The archive timestamp row: the latest anchored time, a claimed
  /// time marked unproven, or a failed token.
  private static func archiveValue(_ stamps: [TimestampState]) -> VerifyDocumentRowValue {
    if let latest = stamps.compactMap(\.provenTime).max() {
      return VerifyDocumentRowValue(text: VerifyText.formatted(latest.date), indicator: .holds)
    }
    if let claimed = stamps.compactMap(\.claimedTime).max() {
      return Self.unprovenValue(claimed)
    }
    return VerifyDocumentRowValue(indicator: .fails)
  }

  private static func unprovenValue(_ claimed: Date) -> VerifyDocumentRowValue {
    VerifyDocumentRowValue(
      text: VerifyText.formatted(claimed),
      secondaryText: VerifyText.text("verify.timestampUnproven", "Unproven")
    )
  }

  /// The level reached, in words rather than the profile's code: the
  /// archival level holds, the others say what the document lacks.
  internal static func levelValue(_ level: SignatureLevel) -> VerifyDocumentRowValue {
    switch level {
    case .longTermArchival:
      VerifyDocumentRowValue(
        text: VerifyText.text("verify.level.archival", "Archival: can be verified for decades"),
        indicator: .holds)

    case .longTerm:
      VerifyDocumentRowValue(
        text: VerifyText.text(
          "verify.level.longTerm", "Validation data included, no archive timestamp"))

    case .timestamped:
      VerifyDocumentRowValue(
        text: VerifyText.text("verify.level.timestamped", "Timestamped, no validation data"))

    case .basic:
      VerifyDocumentRowValue(text: VerifyText.text("verify.level.basic", "Not timestamped"))
    }
  }

  private static func revocationValue(
    _ revocation: RevocationState,
    checking: Bool
  ) -> VerifyDocumentRowValue {
    if checking {
      return VerifyDocumentRowValue(indicator: .progress)
    }
    switch revocation {
    case .good:
      return VerifyDocumentRowValue(indicator: .holds)

    case .revoked:
      return VerifyDocumentRowValue(
        text: VerifyText.text("verify.revoked", "Revoked"), indicator: .fails)

    case .unavailable:
      return VerifyDocumentRowValue(
        secondaryText: VerifyText.text("verify.notChecked", "Not checked"))
    }
  }

  private func judged(_ report: DocumentVerification.SignatureReport) -> some View {
    Section {
      VerifyDocumentRow(indicator: nil) {
        PersonRowLabel(configured: report.isValid)
      } value: {
        Text(DisplayedSignerName.text(of: report.signerCommonName))
          .textSelection(.enabled)
          .accessibilityIdentifier("verifySigner")
      }
      if let issuer = Self.issuer(of: report) {
        Self.row(
          VerifyText.text("verify.issuer", "Issuer"),
          VerifyDocumentRowValue(text: issuer))
      }
      Self.row(VerifyText.text("verify.intact", "Document intact"), holds: report.documentIntact)
      Self.row(VerifyText.text("verify.signature", "Signature"), holds: report.signatureValid)
      Self.row(VerifyText.text("verify.chain", "Certificate chain"), holds: report.chainVerified)
      timeAndStatusRows(report)
    } header: {
      Self.header
    }
  }

  /// The timestamps, the revocation status and the level reached.
  @ViewBuilder
  private func timeAndStatusRows(_ report: DocumentVerification.SignatureReport) -> some View {
    Self.row(VerifyText.text("verify.timestamp", "Timestamp"), Self.timestampValue(of: report))
    if !report.archiveTimestamps.isEmpty {
      Self.row(
        VerifyText.text("verify.archiveTimestamp", "Archive timestamp"),
        Self.archiveValue(report.archiveTimestamps))
    }
    Self.row(
      VerifyText.text("verify.revocation", "Revocation"),
      Self.revocationValue(report.revocation, checking: checking)
    )
    if let level = report.level {
      Self.row(
        VerifyText.text("verify.level", "Long-term validity"),
        Self.levelValue(level)
      )
      .accessibilityIdentifier("verifyLevel")
    }
  }
}
