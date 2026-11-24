// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG

  import CardCore
  import CryptoKit
  import CryptoTokenKit
  import Foundation
  import Security

  /// Diagnostic that runs the full sign path against the real card and
  /// cryptographically verifies the result.
  ///
  /// Run as ``DebugLaunchMode/signProbe``, which owns the flag, the PIN
  /// argument, the printing and the exit status. It selects the app, reads
  /// the leaf, checks the retry floor, verifies PIN1, runs MSE:SET +
  /// PSO:CDS over a SHA-384 test digest, re-encodes the signature, and
  /// verifies it against the card's own public key with
  /// `SecKeyVerifySignature`. A correct PIN does not consume a retry
  /// attempt; this diagnostic requires the PIN1 retry floor but does not
  /// inspect PIN2 or PUK. Not part of the shipping UI.
  ///
  /// The PIN is used and dropped: it is never stored, and nothing below
  /// prints it.
  internal enum SignProbe {
    private final class Box: @unchecked Sendable {
      var lines: [String] = ["sign-probe: no result"]
    }

    /// Raw P-384 signature length (`r || s`), sent as PSO:CDS `Le` up front.
    private static let p384SignatureBytes = 96

    /// What the card did with `pin`, step by step.
    internal static func report(pin: String) -> DebugModeReport {
      DebugModeReport(lines: Self.collect(pin: pin))
    }

    private static func collect(pin: String) -> [String] {
      let semaphore = DispatchSemaphore(value: 0)
      let box = Box()
      Task {
        box.lines = await run(pin: pin)
        semaphore.signal()
      }
      semaphore.wait()
      return box.lines
    }

    private static func run(pin: String) async -> [String] {
      guard
        let manager = TKSmartCardSlotManager.default,
        let found = await CardSlotSearch.occupied(in: manager),
        let smartCard = found.slot.makeSmartCard()
      else {
        return ["FAIL: no reader/card"]
      }
      return cardWork(smartCard: smartCard, pin: pin)
    }

    private static func cardWork(smartCard: TKSmartCard, pin: String) -> [String] {
      var lines: [String] = []
      do {
        return try SmartCardChannel(smartCard).withSession { channel in
          let operations = CardOperations(channel: channel)
          try operations.selectCardApplication()
          let leafDER = try operations.readCertificate(.authentication)
          lines.append("leaf: \(leafDER.count) bytes")

          let pin1 = try operations.probeRetryCounter(role: .pin1)
          lines.append("PIN1 probe: \(String(describing: pin1))")
          guard RetryFloor.evaluate(probeOutcome: pin1) == .proceed else {
            return lines + ["FAIL: retry floor did not permit"]
          }

          guard Pin1(digits: pin) != nil else { return lines + ["FAIL: PIN format"] }
          return lines + signBothDigests(operations, leafDER: leafDER, pin: pin)
        }
      } catch {
        return lines + ["FAIL: \(error)"]
      }
    }

    /// Signs and verifies both TLS hops the card must service.
    ///
    /// suomi.fi is TLS 1.2 and requests ECDSA+SHA-256 (32-byte digest);
    /// card.refineid.fi is TLS 1.3 and requests ECDSA+SHA-384 (48-byte
    /// digest). The P-384 signature is 96 bytes either way. The card
    /// consumes the PIN1 signing authorization per PSO:CDS, so - exactly
    /// like the token extension - each signature re-verifies PIN1 first (a
    /// correct PIN never decrements the retry counter).
    private static func signBothDigests(
      _ operations: CardOperations,
      leafDER: Data,
      pin: String
    ) -> [String] {
      guard
        let publicKey = SecCertificateCreateWithData(nil, leafDER as CFData)
          .flatMap(SecCertificateCopyKey)
      else {
        return ["FAIL: could not extract public key"]
      }
      var lines: [String] = []
      for hash in [SigningHash.sha256, .sha384] {
        do {
          guard let pin1 = Pin1(digits: pin) else {
            lines.append("\(hash): FAIL: PIN format")
            continue
          }
          try operations.verifyPin1(pin1.consumeForSingleTransmission())
          lines.append(
            try signAndVerify(operations: operations, publicKey: publicKey, hash: hash))
        } catch {
          lines.append("\(hash): FAIL: \(error)")
        }
      }
      return lines
    }

    private static func signAndVerify(
      operations: CardOperations,
      publicKey: SecKey,
      hash: SigningHash
    ) throws -> String {
      let message = Data("RefineID signing test".utf8)
      let (digest, secKeyAlgorithm): (Data, SecKeyAlgorithm)
      switch hash {
      case .sha256:
        (digest, secKeyAlgorithm) = (
          Data(SHA256.hash(data: message)), .ecdsaSignatureDigestX962SHA256
        )

      default:
        (digest, secKeyAlgorithm) = (
          Data(SHA384.hash(data: message)), .ecdsaSignatureDigestX962SHA384
        )
      }
      guard let length = ExpectedResponseLength(count: Self.p384SignatureBytes) else {
        return "\(hash): FAIL: bad length"
      }
      let (raw, steps) = try operations.computeAuthenticationSignatureTraced(
        overDigest: digest,
        algorithm: SigningAlgorithm(hash: hash, scheme: .ecdsa),
        expectedSignatureLength: length
      )
      let trace = steps.map { "\($0.command)=\(String(format: "%04X", $0.statusWord))" }
        .joined(separator: " ")
      guard let raw else {
        return "\(hash): [\(trace)] card rejected"
      }
      guard let der = EcdsaSignature.derFromRawConcatenation(raw) else {
        return "\(hash): [\(trace)] FAIL: could not DER-encode \(raw.count) raw bytes"
      }
      var error: Unmanaged<CFError>?
      let valid = SecKeyVerifySignature(
        publicKey,
        secKeyAlgorithm,
        digest as CFData,
        der as CFData,
        &error
      )
      guard valid else {
        let reason = error?.takeRetainedValue().localizedDescription ?? "unknown"
        return "\(hash): [\(trace)] FAIL: does not verify - \(reason)"
      }
      return "\(hash): [\(trace)] raw \(raw.count) B -> DER \(der.count) B -> VERIFIES OK"
    }
  }

#endif
