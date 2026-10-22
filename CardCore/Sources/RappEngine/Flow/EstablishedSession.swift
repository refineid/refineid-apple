// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// A healthy session that carries operations.
internal struct EstablishedSession {
  internal let role: EndpointRole

  internal let pairIdentifier: Data

  internal let sessionIdentifier: Data

  private var channel: RappMessageChannel?

  internal var isOpen: Bool { channel != nil }

  internal init(
    role: EndpointRole,
    pairIdentifier: Data,
    sessionIdentifier: Data,
    channel: RappMessageChannel
  ) {
    self.role = role
    self.pairIdentifier = pairIdentifier
    self.sessionIdentifier = sessionIdentifier
    self.channel = channel
  }

  internal mutating func seal(
    _ messageType: MessageType, body: [String: WireValue]
  ) throws -> Data {
    guard var working = channel else { throw SessionError.closed }
    let frame: Data
    do {
      frame = try working.seal(messageType, body: body)
    } catch {
      throw SessionError.noise
    }
    channel = working
    return frame
  }

  internal mutating func open(_ frame: Data) throws -> Envelope {
    guard var working = channel else { throw SessionError.closed }
    let envelope: Envelope
    do {
      envelope = try working.open(frame)
    } catch RappOpenFailure.sessionIntegrityFailure {
      channel = nil
      throw SessionError.integrityFailure
    } catch {
      // The frame decrypted and its contents broke the protocol. The
      // channel stays open - the cipher state is intact - so the operation
      // bridge can still seal the protocol_violation close before it closes
      // the session (RAPP v26.10.21 §10.1).
      channel = working
      throw SessionError.unexpectedMessage
    }
    channel = working
    return envelope
  }

  /// Close this session locally.
  ///
  /// The pairing itself is untouched.
  internal mutating func close() {
    channel = nil
  }
}
