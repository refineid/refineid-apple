// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// A finished signature stays in memory until it is written or the
  /// holder forgets it. The tests join the serialized virtual card
  /// suite, which owns the shared demo mode.
  extension VirtualIDCardMacOSTests {
    /// Records every file panel request and answers them in order.
    @MainActor
    private final class FilePanel {
      var answers: [SignDocumentModel.PlaceAnswer]
      var offered: [(signed: SignedDocument, typedName: String?)] = []

      init(answers: [SignDocumentModel.PlaceAnswer]) {
        self.answers = answers
      }

      func choose(_ signed: SignedDocument, typedName: String?) -> SignDocumentModel.PlaceAnswer {
        offered.append((signed, typedName))
        guard !answers.isEmpty else {
          return SignDocumentModel.PlaceAnswer(destination: nil, typedName: typedName)
        }
        return answers.removeFirst()
      }
    }

    /// One temporary folder holding the originals.
    private struct Scene {
      let signing: SignDocumentModel
      let folder: URL
      let sources: [URL]

      func remove() {
        try? FileManager.default.removeItem(at: folder)
      }
    }

    /// The virtual card's default PIN 2 in the activated-reader scenario.
    private static let discardPin2 = "123456"

    /// How many main-actor turns a test waits for the model.
    private static let settleTurns = 1_000

    /// Seconds before the folder request covered by a planted collision.
    private static let collisionWindow = 3

    @MainActor
    private static func scene(_ names: [String]) throws -> Scene {
      let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("SignDiscard-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let sources = names.map { folder.appendingPathComponent($0) }
      for source in sources {
        try Data("%PDF-1.4\n% \(source.lastPathComponent)\n%%EOF".utf8).write(to: source)
      }
      let signing = SignDocumentModel()
      signing.accept(sources)
      return Scene(signing: signing, folder: folder, sources: sources)
    }

    private static func cancelled(typing name: String?) -> SignDocumentModel.PlaceAnswer {
      SignDocumentModel.PlaceAnswer(destination: nil, typedName: name)
    }

    private static func chosen(_ url: URL) -> SignDocumentModel.PlaceAnswer {
      SignDocumentModel.PlaceAnswer(destination: url, typedName: url.lastPathComponent)
    }

    /// Yields until `condition` holds; answers whether it did.
    @MainActor
    private static func settle(until condition: () -> Bool) async -> Bool {
      for _ in 0..<Self.settleTurns where !condition() {
        await Task.yield()
      }
      return condition()
    }

    @MainActor
    private static func signing(_ scene: Scene, panel: FilePanel) -> Task<Void, Never> {
      Task { @MainActor in
        await scene.signing.sign(
          pin2: Self.discardPin2, accessNumber: "", format: .pades
        ) { signed, typedName in
          panel.choose(signed, typedName: typedName)
        }
      }
    }

    /// Plants a file under every name `source` could be signed into
    /// within the last few seconds.
    private static func plantCollisions(for source: URL, in folder: URL) throws {
      let now = Date()
      for offset in 0...Self.collisionWindow {
        let instant = now.addingTimeInterval(-TimeInterval(offset))
        let name = SignDocumentModel.suggestedName(for: source, format: .pades, at: instant)
        try Data("planted".utf8).write(to: folder.appendingPathComponent(name))
      }
    }

    @Test
    @MainActor
    internal func savingAfterCancelOffersTheSameSignatureUnderTheTypedName() async throws {
      DemoMode.shared.activate(scenario: .activatedReader)
      defer { DemoMode.shared.deactivate() }
      let scene = try Self.scene(["Agreement.pdf"])
      defer { scene.remove() }
      let destination = scene.folder.appendingPathComponent("Typed.pdf")
      let panel = FilePanel(answers: [
        Self.cancelled(typing: "Typed.pdf"), Self.chosen(destination),
      ])

      let task = Self.signing(scene, panel: panel)
      #expect(await Self.settle { scene.signing.unsaved != nil })
      #expect(scene.signing.unsaved == .one)
      #expect(scene.signing.working)
      scene.signing.answerUnsaved(forget: false)
      await task.value

      #expect(panel.offered.count == 2)
      let first = try #require(panel.offered.first)
      let second = try #require(panel.offered.last)
      #expect(first.typedName == nil)
      #expect(second.typedName == "Typed.pdf")
      #expect(first.signed.bytes == second.signed.bytes)
      #expect(first.signed.bestSignatureTime == second.signed.bestSignatureTime)
      #expect(scene.signing.unsaved == nil)
      #expect(scene.signing.signed == destination)
      #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    @MainActor
    internal func forgettingAfterCancelWritesNothing() async throws {
      DemoMode.shared.activate(scenario: .activatedReader)
      defer { DemoMode.shared.deactivate() }
      let scene = try Self.scene(["Agreement.pdf"])
      defer { scene.remove() }
      let destination = scene.folder.appendingPathComponent("Unused.pdf")
      let panel = FilePanel(answers: [Self.cancelled(typing: nil), Self.chosen(destination)])

      let task = Self.signing(scene, panel: panel)
      #expect(await Self.settle { scene.signing.unsaved != nil })
      scene.signing.answerUnsaved(forget: true)
      await task.value

      #expect(panel.offered.count == 1)
      #expect(scene.signing.unsaved == nil)
      #expect(scene.signing.failure == nil)
      #expect(scene.signing.signed == nil)
      #expect(scene.signing.pending == scene.sources.first)
      #expect(!scene.signing.working)
      #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    @MainActor
    internal func dismissingTheAlertCountsAsSaving() async throws {
      DemoMode.shared.activate(scenario: .activatedReader)
      defer { DemoMode.shared.deactivate() }
      let scene = try Self.scene(["Agreement.pdf"])
      defer { scene.remove() }
      let destination = scene.folder.appendingPathComponent("Kept.pdf")
      let panel = FilePanel(answers: [Self.cancelled(typing: nil), Self.chosen(destination)])

      let task = Self.signing(scene, panel: panel)
      #expect(await Self.settle { scene.signing.unsaved != nil })
      scene.signing.dismissUnsaved()
      await task.value

      #expect(panel.offered.count == 2)
      #expect(scene.signing.signed == destination)
    }

    /// A place that is the original under another letter case is
    /// refused, the refusal is shown, and the panel asks again.
    @Test
    @MainActor
    internal func choosingTheOriginalAsksAgain() async throws {
      DemoMode.shared.activate(scenario: .activatedReader)
      defer { DemoMode.shared.deactivate() }
      let scene = try Self.scene(["Agreement.pdf"])
      defer { scene.remove() }
      let source = try #require(scene.sources.first)
      let original = try Data(contentsOf: source)
      let respelled = scene.folder.appendingPathComponent("AGREEMENT.pdf")
      let destination = scene.folder.appendingPathComponent("Signed.pdf")
      let panel = FilePanel(answers: [Self.chosen(respelled), Self.chosen(destination)])

      let task = Self.signing(scene, panel: panel)
      #expect(await Self.settle { scene.signing.failure != nil })
      #expect(
        scene.signing.failure
          == String(localized: "The signed document cannot replace the original.")
      )
      scene.signing.acknowledgeFailure()
      await task.value

      #expect(panel.offered.count == 2)
      #expect(panel.offered.last?.typedName == "AGREEMENT.pdf")
      #expect(try Data(contentsOf: source) == original)
      #expect(scene.signing.signed == destination)
    }

    @Test
    @MainActor
    internal func aFailedWriteAsksAgain() async throws {
      DemoMode.shared.activate(scenario: .activatedReader)
      defer { DemoMode.shared.deactivate() }
      let scene = try Self.scene(["Agreement.pdf"])
      defer { scene.remove() }
      let unreachable = scene.folder.appendingPathComponent("Missing")
        .appendingPathComponent("Signed.pdf")
      let destination = scene.folder.appendingPathComponent("Signed.pdf")
      let panel = FilePanel(answers: [Self.chosen(unreachable), Self.chosen(destination)])

      let task = Self.signing(scene, panel: panel)
      #expect(await Self.settle { scene.signing.failure != nil })
      scene.signing.acknowledgeFailure()
      await task.value

      #expect(panel.offered.count == 2)
      #expect(scene.signing.signed == destination)
      #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    @MainActor
    internal func aContainerKeptAfterCancelIsWritten() async throws {
      DemoMode.shared.activate(scenario: .activatedReader)
      defer { DemoMode.shared.deactivate() }
      let scene = try Self.scene(["Ledger.ods", "Notes.txt"])
      defer { scene.remove() }
      let destination = scene.folder.appendingPathComponent("Pile.asice")
      let panel = FilePanel(answers: [Self.cancelled(typing: "Pile"), Self.chosen(destination)])

      let task = Task { @MainActor in
        await scene.signing.signTogether(pin2: Self.discardPin2) { signed, typedName in
          panel.choose(signed, typedName: typedName)
        }
      }
      #expect(await Self.settle { scene.signing.unsaved != nil })
      #expect(scene.signing.unsaved == .one)
      scene.signing.answerUnsaved(forget: false)
      await task.value

      #expect(panel.offered.count == 2)
      #expect(panel.offered.last?.typedName == "Pile")
      #expect(scene.signing.signed == destination)
    }

    @Test
    @MainActor
    internal func aPileAsksForItsFolderOnceAndReportsACollision() async throws {
      DemoMode.shared.activate(scenario: .activatedReader)
      defer { DemoMode.shared.deactivate() }
      let scene = try Self.scene(["First.pdf", "Second.pdf"])
      defer { scene.remove() }
      let output = scene.folder.appendingPathComponent("Signed")
      try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
      let first = try #require(scene.sources.first)
      var requests = 0

      await scene.signing.signAll(
        pin2: Self.discardPin2, accessNumber: "", format: .pades
      ) {
        requests += 1
        try? Self.plantCollisions(for: first, in: output)
        return output
      }

      #expect(requests == 1)
      let written = try FileManager.default.contentsOfDirectory(atPath: output.path)
      #expect(written.contains { $0.hasPrefix("Second") })
      #expect(
        written.filter { $0.hasPrefix("First") }.allSatisfy { name in
          (try? Data(contentsOf: output.appendingPathComponent(name))) == Data("planted".utf8)
        }
      )
      let outcomes = scene.signing.batchOutcomes
      #expect(outcomes.count == 2)
      #expect(outcomes.first?.hasPrefix("First.pdf: ") == true)
      #expect(scene.signing.failure?.contains("First.pdf") == true)
      #expect(!scene.signing.working)
    }

    @Test
    @MainActor
    internal func aPileKeptAfterCancelAsksForItsFolderAgain() async throws {
      DemoMode.shared.activate(scenario: .activatedReader)
      defer { DemoMode.shared.deactivate() }
      let scene = try Self.scene(["First.pdf", "Second.pdf"])
      defer { scene.remove() }
      let output = scene.folder.appendingPathComponent("Signed")
      try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
      var answers: [URL?] = [nil, output]

      let task = Task { @MainActor in
        await scene.signing.signAll(
          pin2: Self.discardPin2, accessNumber: "", format: .pades
        ) {
          answers.isEmpty ? nil : answers.removeFirst()
        }
      }
      #expect(await Self.settle { scene.signing.unsaved != nil })
      #expect(scene.signing.unsaved == .several)
      scene.signing.answerUnsaved(forget: false)
      await task.value

      #expect(answers.isEmpty)
      #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).count == 2)
      #expect(scene.signing.batchOutcomes.count == 2)
      #expect(scene.signing.failure == nil)
    }

    /// A document whose failure went with the card is still reported.
    @Test
    internal func aRefusalWithoutAFailureIsStillReported() {
      #expect(!SignDocumentModel.refusal(after: nil).isEmpty)
      #expect(SignDocumentModel.refusal(after: "Refused") == "Refused")
    }

    /// The same file through a symbolic link, or in another letter
    /// case, is an original.
    @Test
    internal func originalsAreMatchedThroughLinksAndCase() throws {
      let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("SignOriginal-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: folder) }
      let original = folder.appendingPathComponent("Agreement.pdf")
      try Data("original".utf8).write(to: original)
      let link = folder.appendingPathComponent("Link")
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)

      #expect(
        SignDocumentModel.isOriginal(
          link.appendingPathComponent("Agreement.pdf"), among: [original]
        )
      )
      #expect(
        SignDocumentModel.isOriginal(
          folder.appendingPathComponent("agreement.PDF"), among: [original]
        )
      )
      #expect(
        !SignDocumentModel.isOriginal(
          folder.appendingPathComponent("Other.pdf"), among: [original]
        )
      )
    }
  }

#endif
