// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import RefineID

  /// Direct checks for the compact, human-readable QR envelope.
  @Suite
  internal struct StampAttestationTests {
    @Test
    internal func claimIsTheExactCanonicalOneLine() throws {
      let claim = try #require(
        StampAttestation.claim(
          identifier: "010101-000a",
          filename: "Résumé_日本.pdf",
          at: Date(timeIntervalSince1970: 1_785_920_400.9)
        )
      )

      #expect(
        claim.text == "RID1/010101-000A/1785920400/RESUME.PDF"
      )
      #expect(claim.bytes == Data(claim.text.utf8))
    }

    @Test
    internal func longFilenameKeepsItsExtensionAndBound() {
      let filename = String(repeating: "A", count: 80) + ".PDF"

      let canonical = StampAttestation.canonicalFilename(filename)

      #expect(canonical.count == StampAttestation.maximumFilenameLength)
      #expect(canonical.hasSuffix(".PDF"))
    }

    @Test
    internal func missingIdentifierCannotMakeAClaim() {
      #expect(
        StampAttestation.claim(
          identifier: "",
          filename: "document.pdf",
          at: Date(timeIntervalSince1970: 0)
        ) == nil
      )
    }

    @Test
    internal func payloadCarriesKeyIdAndRecoverableSignature() throws {
      let claim = try #require(
        StampAttestation.claim(
          identifier: "010101-000A",
          filename: "document.pdf",
          at: Date(timeIntervalSince1970: 1_785_920_400)
        )
      )
      let signature = Data((0..<104).map { UInt8($0) })
      let payload = StampAttestation.payload(
        claim: claim,
        signerCertificate: Data("certificate".utf8),
        signature: signature
      )
      let text = try #require(String(data: payload, encoding: .utf8))
      let fields = text.split(separator: "/", maxSplits: 5)

      #expect(fields.count == 6)
      #expect(fields[0] == "RID1")
      #expect(fields[1] == "010101-000A")
      #expect(fields[2] == "1785920400")
      #expect(fields[3] == "DOCUMENT.PDF")
      #expect(fields[4] == "03D66DD08835")
      #expect(Base45.decode(String(fields[5])) == signature)
    }

    @Test
    internal func worstCaseEccPayloadRemainsSixtyNineModules() throws {
      let claim = try #require(
        StampAttestation.claim(
          identifier: "010101-000A",
          filename: String(repeating: "A", count: 44) + ".PDF",
          at: Date(timeIntervalSince1970: 1_785_920_400)
        )
      )
      let payload = StampAttestation.payload(
        claim: claim,
        signerCertificate: Data("certificate".utf8),
        signature: Data(repeating: 0xA5, count: 104)
      )

      #expect(QrCode.modules(of: payload)?.side == 69)
    }
  }

#endif
