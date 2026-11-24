// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// Diagnostic PKCS#15 inventory logging split from `Token+Unseal.swift`.
extension Token {
  /// Records what the card's own directories say it carries.
  internal static func reportInventory(read operations: CardOperations) {
    let entries: [Pkcs15Inventory.Entry]
    do {
      entries = try operations.readPkcs15Inventory()
    } catch {
      TokenLog.info("readIdentity: PKCS#15 inventory unreadable (\(error))")
      return
    }
    TokenLog.info("readIdentity: PKCS#15 inventory lists \(entries.count) certificates")
    for entry in entries {
      let identifierHex = entry.certificate.identifier
        .map { byte in
          String(format: "%02X", byte)
        }
        .joined()
      let keyReferenceHex =
        entry.key?.keyReference.map { byte in
          String(format: "%02X", byte)
        } ?? "none"
      TokenLog.info(
        "readIdentity: inventory entry file=\(entry.certificate.file) "
          + "id=\(identifierHex) "
          + "key=\(entry.key != nil) "
          + "keyReference=\(keyReferenceHex)"
      )
    }
  }
}
