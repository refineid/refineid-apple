// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG

  import CardCore
  import CryptoTokenKit
  import Foundation
  import Security

  /// Diagnostic that runs the token-publish pipeline from the app.
  ///
  /// Card I/O is unconstrained here, so this bisects cert-reading logic
  /// from ctkd invocation. Run as ``DebugLaunchMode/tokenPublishProbe``,
  /// which owns the flag, the printing and the exit status. Not part of
  /// the shipping UI.
  internal enum TokenPublishProbe {
    private final class ProbeBox: @unchecked Sendable {
      var lines: [String] = ["probe: no result"]
    }

    /// What the pipeline did, step by step.
    internal static func report() -> DebugModeReport {
      DebugModeReport(lines: Self.collect())
    }

    private static func collect() -> [String] {
      var lines: [String] = []
      let watcher = TKTokenWatcher()
      lines.append("token watcher: \(watcher.tokenIDs.count) token(s)")
      for tokenID in watcher.tokenIDs.sorted() where tokenID.hasPrefix("fi.refineid.") {
        lines.append("  refineid token present: \(tokenID)")
      }

      let semaphore = DispatchSemaphore(value: 0)
      let box = ProbeBox()
      Task {
        box.lines = await readAndBuild()
        semaphore.signal()
      }
      semaphore.wait()
      return lines + box.lines
    }

    private static func readAndBuild() async -> [String] {
      var lines: [String] = []
      guard let manager = TKSmartCardSlotManager.default else {
        return ["FAIL: no slot manager"]
      }
      guard let slotName = manager.slotNames.first else {
        return ["FAIL: no reader slot"]
      }
      lines.append("slot: \(slotName)")
      guard
        let slot = await manager.getSlot(withName: slotName),
        let smartCard = slot.makeSmartCard()
      else {
        return lines + ["FAIL: no card"]
      }
      do {
        return try SmartCardChannel(smartCard).withSession { channel in
          let operations = CardOperations(channel: channel)
          try operations.selectCardApplication()
          lines.append("select application: OK")
          let leaf = try operations.readCertificate(.authentication)
          lines.append("read leaf EF.4331: \(leaf.count) bytes")
          let issuer = try? operations.readCertificate(.issuing)
          lines.append("read issuer EF.4336: \(issuer?.count ?? -1) bytes")
          return lines + buildKeychainItems(leaf: leaf)
        }
      } catch {
        return lines + ["FAIL during read: \(error)"]
      }
    }

    private static func buildKeychainItems(leaf: Data) -> [String] {
      var lines: [String] = []
      guard let certificate = SecCertificateCreateWithData(nil, leaf as CFData) else {
        return ["FAIL: SecCertificateCreateWithData(leaf) returned nil"]
      }
      lines.append("SecCertificate(leaf): OK")
      if let key = SecCertificateCopyKey(certificate),
        let attributes = SecKeyCopyAttributes(key) as? [CFString: Any]
      {
        let type = (attributes[kSecAttrKeyType] as? String) ?? "?"
        let size = (attributes[kSecAttrKeySizeInBits] as? Int) ?? -1
        lines.append("key: type=\(type) size=\(size)")
      } else {
        lines.append("FAIL: could not copy key attributes")
      }
      let objectID = "auth"
      if TKTokenKeychainCertificate(certificate: certificate, objectID: objectID) != nil {
        lines.append("TKTokenKeychainCertificate: OK")
      } else {
        lines.append("FAIL: TKTokenKeychainCertificate nil")
      }
      if TKTokenKeychainKey(certificate: certificate, objectID: objectID) != nil {
        lines.append("TKTokenKeychainKey: OK")
      } else {
        lines.append("FAIL: TKTokenKeychainKey nil")
      }
      return lines
    }
  }

#endif
