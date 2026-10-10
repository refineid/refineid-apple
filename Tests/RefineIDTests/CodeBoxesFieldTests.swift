// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Testing

  @testable import RefineID

  /// What one edit of a box field keeps, and when it submits.
  @Suite
  internal struct CodeBoxesFieldTests {
    private enum Fixture {
      static let length = RappPairingCode.codeLength

      static func filter(_ typed: String) -> String {
        RemotePairingPromptView.limitedCode(typed)
      }
    }

    @Test
    internal func partialEntryDoesNotSubmit() {
      let edit = CodeBoxesField.edit(
        from: "7K", to: "7KX", length: Fixture.length, filter: Fixture.filter)
      #expect(edit == CodeBoxesField.Edit(text: "7KX", completes: false))
    }

    @Test
    internal func lastCharacterSubmits() {
      let edit = CodeBoxesField.edit(
        from: "7KX4M", to: "7KX4M9", length: Fixture.length, filter: Fixture.filter)
      #expect(edit == CodeBoxesField.Edit(text: "7KX4M9", completes: true))
    }

    @Test
    internal func pastedCodeIsCleanedAndSubmits() {
      let edit = CodeBoxesField.edit(
        from: "", to: "7k x4-m9", length: Fixture.length, filter: Fixture.filter)
      #expect(edit == CodeBoxesField.Edit(text: "7KX4M9", completes: true))
    }

    @Test
    internal func refilteringAFullCodeDoesNotSubmitAgain() {
      let edit = CodeBoxesField.edit(
        from: "7k x4-m9", to: "7KX4M9", length: Fixture.length, filter: Fixture.filter)
      #expect(!edit.completes)
    }

    @Test
    internal func overlongInputStopsAtTheLastBox() {
      let edit = CodeBoxesField.edit(
        from: "7KX4M9", to: "7KX4M9A", length: Fixture.length, filter: Fixture.filter)
      #expect(edit == CodeBoxesField.Edit(text: "7KX4M9", completes: false))
    }

    @Test
    internal func accessNumberKeepsDigitsOnly() {
      let edit = CodeBoxesField.edit(
        from: "", to: "12a3 456", length: CardAccessNumber.digitCount,
        filter: LimitedDigits.cardAccessNumber)
      #expect(edit == CodeBoxesField.Edit(text: "123456", completes: true))
    }
  }

#endif
