// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The paired phone's line: what the phone says.
  ///
  /// The line carries no control of its own: the remote-use switch is the
  /// pairing, and turning it off forgets the phone (hierarchy specification
  /// §5.2).
  internal struct PairedPhoneLine: View {
    /// What the line says.
    internal let lead: IdentityLine.PairedLead

    /// The holder's name from the certificate the phone confirmed, once
    /// read.
    internal let holder: String?

    internal var body: some View {
      Text(Self.line(lead: lead, holder: holder))
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The words of the line: the holder's name in the primary color,
    /// everything else in the secondary one.
    ///
    /// The holder's line ends with "(via phone)". Until the holder's name
    /// is read, the line says it is connecting.
    nonisolated internal static func line(
      lead: IdentityLine.PairedLead, holder: String?
    ) -> AttributedString {
      switch lead {
      case .connecting:
        return Self.connecting()

      case .holder:
        guard let holder, !holder.isEmpty else { return Self.connecting() }
        var line = AttributedString(holder)
        line.append(Self.secondary(" " + String(localized: "(via phone)")))
        return line

      case .phoneReader:
        return Self.secondary(PhoneCardRequestLine.instruction(for: .insertIntoPhoneReader))
      }
    }

    nonisolated private static func connecting() -> AttributedString {
      Self.secondary(String(localized: "Connecting to the phone…"))
    }

    nonisolated private static func secondary(_ words: String) -> AttributedString {
      var styled = AttributedString(words)
      styled[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = .secondary
      return styled
    }
  }

#endif
