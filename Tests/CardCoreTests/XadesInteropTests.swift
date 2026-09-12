// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// The signature checked by a verifier that is not ours.
///
/// Every other XAdES test inspects our own output with our own
/// expectations, which cannot catch the failure the writer is built to
/// avoid: output that is well-formed XML but not in canonical form.
/// Only an independent canonicaliser can. `xmlsec1` canonicalises
/// `SignedInfo` itself, recomputes every reference digest, and checks
/// the signature - so if it agrees, the octets we signed are the
/// octets a verifier computes. The keys come from `openssl`, standing
/// in for the card.
///
/// Skipped silently when the two tools are not installed; the RefineID
/// build gates do not require them.
@Suite
internal struct XadesInteropTests {
  /// Where Homebrew and the system keep the external tools.
  private static let toolDirectories = [
    "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
  ]

  /// The instant the fixture claims to have signed at.
  private static let signedAt = Date(timeIntervalSince1970: 1_785_849_296)

  /// Whether both external verifiers are installed.
  private static var toolsAvailable: Bool {
    Self.tool("xmlsec1") != nil && Self.tool("openssl") != nil
  }

  /// The first installed location of a named tool, or nil.
  private static func tool(_ name: String) -> URL? {
    Self.toolDirectories
      .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
      .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  /// Runs one tool in `directory`, answering combined output and
  /// status.
  ///
  /// The working directory matters: `xmlsec1` resolves a relative
  /// reference URI against the process's directory rather than the
  /// document's, so it has to be run from inside the container.
  @discardableResult
  private static func run(
    _ name: String,
    _ arguments: [String],
    in directory: URL,
    expectSuccess: Bool = true
  ) throws -> (status: Int32, report: String) {
    let process = Process()
    let executable = try #require(Self.tool(name))
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = directory
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let report = String(
      bytes: pipe.fileHandleForReading.readDataToEndOfFile(),
      encoding: .utf8
    )
    let text = try #require(report)
    if expectSuccess {
      try #require(
        process.terminationStatus == 0,
        "\(name) \(arguments) failed:\n\(text)"
      )
    }
    return (process.terminationStatus, text)
  }

  /// A fresh RSA-2048 key and certificate standing in for the card.
  private static func certificate(in directory: URL) throws -> Data {
    try Self.run(
      "openssl",
      [
        "req", "-x509", "-newkey", "rsa:2048", "-sha384", "-days", "1",
        "-nodes", "-subj", "/CN=RefineID XAdES interop",
        "-keyout", "key.pem", "-out", "cert.pem",
      ],
      in: directory
    )
    try Self.run(
      "openssl",
      ["x509", "-in", "cert.pem", "-outform", "der", "-out", "cert.der"],
      in: directory
    )
    return try Data(contentsOf: directory.appendingPathComponent("cert.der"))
  }

  /// The container's files, written where the reference URIs point.
  private static func objects(in directory: URL) throws
    -> [AsicContainer.DataObject]
  {
    let objects = [
      AsicContainer.DataObject(
        name: "dossier.pdf",
        mimeType: "application/pdf",
        content: Data("RefineID XAdES interoperability dossier".utf8)
      ),
      AsicContainer.DataObject(
        name: "Nimetön.docx",
        mimeType: "text/plain",
        content: Data("annex one, completed and signed".utf8)
      ),
    ]
    for object in objects {
      try object.content.write(
        to: directory.appendingPathComponent(object.name)
      )
    }
    return objects
  }

  /// Signs exactly the plan's octets with the fixture key.
  private static func signature(
    of plan: XadesSignature.Plan,
    in directory: URL
  ) throws -> Data {
    try plan.signedInfo.write(
      to: directory.appendingPathComponent("signedinfo.xml")
    )
    try Self.run(
      "openssl",
      [
        "dgst", "-sha384", "-sign", "key.pem",
        "-out", "signature.bin", "signedinfo.xml",
      ],
      in: directory
    )
    return try Data(
      contentsOf: directory.appendingPathComponent("signature.bin")
    )
  }

  /// The arguments telling `xmlsec1` which attribute the
  /// same-document reference resolves against.
  ///
  /// Nothing in the document declares it, because a container carries
  /// no DTD or schema, so every verifier of this format is told the
  /// same thing out of band.
  private static func verifyArguments(trustedPem: String) -> [String] {
    [
      "--verify", "--verbose", "--trusted-pem", trustedPem,
      "--id-attr:Id",
      "http://uri.etsi.org/01903/v1.3.2#:SignedProperties",
      "META-INF/signatures0.xml",
    ]
  }

  /// The finished container over fresh fixtures, signed with the
  /// `openssl` key standing in for the card.
  private static func signedContainer(
    objects: [AsicContainer.DataObject],
    in directory: URL
  ) throws -> Data {
    let certificate = try Self.certificate(in: directory)
    let plan = try #require(
      XadesSignature.plan(
        objects: objects,
        certificate: certificate,
        profile: .rsa2048,
        signedAt: Self.signedAt
      )
    )
    let document = plan.document(
      xmlSignature: try Self.signature(of: plan, in: directory),
      timestampTokens: [],
      material: PdfValidationStore.Material(
        certificates: [], ocspResponses: [], revocationLists: []
      )
    )
    return try #require(
      AsicContainer.container(objects: objects, signatureXml: document)
    )
  }

  /// The whole pipeline, through a real container: signed here,
  /// taken apart by `unzip`, verified by `xmlsec1`, and refused once
  /// a data object changes.
  @Test(.enabled(if: Self.toolsAvailable))
  internal func xmlsec1VerifiesTheContainerAndRefusesTampering() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("xades-interop-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let objects = try Self.objects(in: directory)
    let container = try Self.signedContainer(objects: objects, in: directory)
    try container.write(to: directory.appendingPathComponent("out.asice"))

    // Taken apart by a reader that knows nothing about us, then
    // verified from the archive root, which is where a container
    // reader resolves the reference URIs from.
    let extracted = directory.appendingPathComponent("extracted")
    _ = try Self.run(
      "unzip", ["-o", "-q", "out.asice", "-d", "extracted"], in: directory
    )
    let verified = try Self.run(
      "xmlsec1",
      Self.verifyArguments(trustedPem: "../cert.pem"),
      in: extracted
    )
    #expect(
      verified.report.contains("Verification status: OK"),
      "xmlsec1 did not verify the signature:\n\(verified.report)"
    )
    // Every reference, not just the easy ones. The last covers
    // SignedProperties, the subtree whose canonical form the writer
    // has to get right without a canonicaliser; a verifier that
    // skipped it would report OK for the wrong reason.
    #expect(
      verified.report.contains("SignedInfo References (ok/all): 3/3"),
      "xmlsec1 must have checked every reference:\n\(verified.report)"
    )

    // A verifier that says OK to a changed document says nothing at
    // all. Change one data object and it must refuse.
    try Data("tampered".utf8).write(
      to: extracted.appendingPathComponent("dossier.pdf")
    )
    let tampered = try Self.run(
      "xmlsec1",
      Self.verifyArguments(trustedPem: "../cert.pem"),
      in: extracted,
      expectSuccess: false
    )
    #expect(
      tampered.status != 0,
      "a changed data object must break the signature:\n\(tampered.report)"
    )
  }
}
