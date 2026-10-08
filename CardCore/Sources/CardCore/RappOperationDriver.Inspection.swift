// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation

  extension RappOperationDriver {
    /// Card factory and retry state produced by an inspection.
    public struct Inspection: Sendable, Equatable {
      /// The card's answer to reset or its historical bytes; empty when the
      /// platform exposes neither.
      public let answerToReset: Data
      /// Whether PIN 1 still carries its factory value.
      public let pin1Factory: Bool
      /// Whether PIN 2 still carries its factory value.
      public let pin2Factory: Bool
      /// Remaining PIN 1 attempts when reported.
      public let pin1Attempts: UInt8?
      /// Remaining PIN 2 attempts when reported.
      public let pin2Attempts: UInt8?
      /// Remaining PUK attempts when reported.
      public let pukAttempts: UInt8?

      /// Creates an inspection result describing card state.
      public init(
        pin1Factory: Bool,
        pin2Factory: Bool,
        pin1Attempts: UInt8? = nil,
        pin2Attempts: UInt8? = nil,
        pukAttempts: UInt8? = nil,
        answerToReset: Data = Data()
      ) {
        self.answerToReset = answerToReset
        self.pin1Factory = pin1Factory
        self.pin2Factory = pin2Factory
        self.pin1Attempts = pin1Attempts
        self.pin2Attempts = pin2Attempts
        self.pukAttempts = pukAttempts
      }
    }
  }
#endif
