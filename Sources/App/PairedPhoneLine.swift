// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The paired phone's line: what the phone says, then the phone's name
  /// in the secondary color, and the control that forgets the pairing.
  ///
  /// The control stands whatever the phone says, a phone with no card or
  /// one out of reach included, so every pairing can be removed from here.
  internal struct PairedPhoneLine: View {
    /// What the line says before the phone's name.
    internal let lead: IdentityLine.PairedLead

    /// The phone, by the name it introduced itself with.
    internal let phone: String

    /// The holder's name from the certificate the phone confirmed, once
    /// read.
    internal let holder: String?

    internal var body: some View {
      HStack {
        Text(Self.line(lead: lead, phone: phone, holder: holder))
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button {
          Task {
            await PersistentTokenRegistry.shared.forgetPairedPhone(through: RappPairingModel())
          }
        } label: {
          Image(systemName: "person.badge.minus")
        }
        .buttonStyle(.borderless)
        .help(Text("Remove phone pairing"))
        .accessibilityLabel(Text("Remove phone pairing"))
        .accessibilityIdentifier("forgetPairedPhone")
      }
    }

    /// The words of the line: the holder's name in the primary color,
    /// everything else in the secondary one.
    ///
    /// With nothing to say before it, the phone's name stands alone.
    nonisolated internal static func line(
      lead: IdentityLine.PairedLead, phone: String, holder: String?
    ) -> AttributedString {
      guard let opening = Self.opening(lead: lead, holder: holder) else {
        return Self.secondary(String(localized: "Paired phone: \(phone)"))
      }
      var line =
        lead == .holder ? AttributedString(opening) : Self.secondary(opening)
      line.append(Self.secondary(" " + String(localized: "(paired phone: \(phone))")))
      return line
    }

    /// What is said before the phone's name; nil when nothing is.
    nonisolated private static func opening(lead: IdentityLine.PairedLead, holder: String?)
      -> String?
    {
      switch lead {
      case .away:
        nil

      case .connecting:
        String(localized: "Connecting...")

      case .holder:
        holder.flatMap { $0.isEmpty ? nil : $0 }

      case .insertCard:
        String(localized: "Insert the card into the reader.")

      case .phoneCard(let request):
        PhoneCardRequestLine.instruction(for: request)
      }
    }

    nonisolated private static func secondary(_ words: String) -> AttributedString {
      var styled = AttributedString(words)
      styled[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = .secondary
      return styled
    }
  }

#endif
