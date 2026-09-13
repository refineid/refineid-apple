// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

@_spi(TokenExtension) import CardCore
// swiftlint:disable:previous attributes
import CryptoTokenKit
import Foundation
import OSLog
import RappEngine
import Security

/// Generic persistent-token principal selected by the extension plist.
///
/// The direct smart-card driver remains a separate extension on every
/// platform; this driver owns only the delegated persistent identity.
internal final class PersistentTokenDriver: TKTokenDriver,
  TKTokenDriverDelegate
{
  private final class PersistentToken: TKToken, TKTokenDelegate {
    private static let logger = Logger(subsystem: "fi.refineid.ReFineID", category: "rapp-token")
    fileprivate let certificate: SecCertificate
    fileprivate let publicKey: SecKey
    fileprivate let profile: CardKeyProfile
    fileprivate let pairRecord: RappPairRecord?

    fileprivate init(
      tokenDriver: TKTokenDriver,
      configuration: TKToken.Configuration
    ) throws {
      let item = try configuration.certificate(
        for: PersistentTokenIdentity.certificateObjectID
      )
      guard
        let parsedCertificate = SecCertificateCreateWithData(nil, item.data as CFData),
        let parsedPublicKey = SecCertificateCopyKey(parsedCertificate),
        let resolvedProfile = CardKeyProfile.resolve(fromPublicKey: parsedPublicKey)
      else {
        throw TKError(.corruptedData)
      }
      self.certificate = parsedCertificate
      self.publicKey = parsedPublicKey
      self.profile = resolvedProfile
      if let configData = configuration.configurationData {
        self.pairRecord = try? RappPairRecord.decode(from: configData)
      } else {
        self.pairRecord = nil
      }
      #if DEBUG
        NSLog(
          "[PersistentToken] init instanceID=%{public}@ hasConfigData=%{public}s hasPairRecord=%{public}s",
          configuration.instanceID,
          configuration.configurationData != nil ? "true" : "false",
          self.pairRecord != nil ? "true" : "false"
        )
      #endif
      super.init(tokenDriver: tokenDriver, instanceID: configuration.instanceID)
      delegate = self
    }

    /// The @objc delegate requirement fixes the throwing signature even
    /// though this implementation cannot fail.
    fileprivate func createSession(
      _: TKToken
    ) throws -> TKTokenSession {  // swiftlint:disable:this unneeded_throws_rethrows
      PersistentTokenSession(token: self)
    }
  }

  private final class PersistentTokenSession: TKTokenSession,
    TKTokenSessionDelegate
  {
    private static let logger = Logger(subsystem: "fi.refineid.ReFineID", category: "rapp-token")

    /// The requesting surface named on the authorizer's approval sheet.
    private static var displayContext: String {
      #if os(macOS)
        "macOS CryptoTokenKit"
      #else
        "iOS CryptoTokenKit"
      #endif
    }

    /// Milliseconds in one second, for the ages this token reports.
    private static let millisecondsPerSecond = 1_000.0

    private let persistentToken: PersistentToken

    fileprivate init(token: PersistentToken) {
      persistentToken = token
      super.init(token: token)
      delegate = self
    }

    /// Records what this token did with a browser's request.
    ///
    /// A signature the card made and this token refuses is the one failure
    /// that leaves no trace anywhere: the browser is told only that the
    /// data was corrupt, asks again, and is refused again.
    /// How long ago, in whole milliseconds.
    private static func millisecondsSince(_ started: Date) -> Int {
      Int(Date().timeIntervalSince(started) * Self.millisecondsPerSecond)
    }

    private static func say(_ line: String) {
      #if DEBUG
        Self.logger.notice("[PersistentTokenDriver] \(line, privacy: .public)")
        ExtensionTrace.record(line)
        ExtensionTrace.flush()
      #endif
    }

    fileprivate func tokenSession(
      _: TKTokenSession,
      supports operation: TKTokenOperation,
      keyObjectID: Any,
      algorithm: TKTokenKeyAlgorithm
    ) -> Bool {
      let supported =
        operation == .signData
        && (keyObjectID as? String) == PersistentTokenIdentity.keyObjectID
        && SigningAlgorithmResolver.advertises(
          algorithm,
          profile: persistentToken.profile
        )
      #if DEBUG
        print(
          """
          [PersistentTokenDriver] supports: op=\(operation.rawValue) \
          algo=\(SigningAlgorithmResolver.describe(algorithm)) \
          profile=\(String(describing: persistentToken.profile)) -> \(supported)
          """
        )
        fflush(stdout)
      #endif
      return supported
    }

    fileprivate func tokenSession(
      _: TKTokenSession,
      sign dataToSign: Data,
      keyObjectID: Any,
      algorithm: TKTokenKeyAlgorithm
    ) throws -> Data {
      guard
        (keyObjectID as? String) == PersistentTokenIdentity.keyObjectID,
        let request = SigningAlgorithmResolver.resolve(
          algorithm,
          input: dataToSign,
          profile: persistentToken.profile
        ),
        let relayAlgorithm = RappOperationDriver.SignatureAlgorithm(request.algorithm)
      else {
        throw TKError(.notImplemented)
      }
      let started = Date()
      Self.say("rapp sign asked")
      let raw = try performRelaySign(
        request: request,
        algorithm: relayAlgorithm,
        started: started
      )
      let signature: Data
      if request.isSatisfied(by: raw, from: persistentToken.publicKey) {
        signature = raw
      } else if let converted = request.wireSignature(from: raw),
        request.isSatisfied(by: converted, from: persistentToken.publicKey)
      {
        signature = converted
      } else {
        #if DEBUG
          let elapsed = Self.millisecondsSince(started)
          Self.logger.notice(
            "[PersistentTokenDriver] rapp sign rejected (length \(raw.count)) after \(elapsed) ms"
          )
        #endif
        Self.say("rapp sign rejected after \(Self.millisecondsSince(started)) ms")
        throw TKError(.corruptedData)
      }
      Self.say("rapp sign served after \(Self.millisecondsSince(started)) ms")
      return signature
    }

    private func performRelaySign(
      request: SignRequest,
      algorithm: RappOperationDriver.SignatureAlgorithm,
      started: Date
    ) throws -> Data {
      do {
        #if DEBUG
          Self.say(
            "performRelaySign: starting algorithm=\(algorithm), digest=\(request.digest.count) bytes"
          )
        #endif
        let response = try RappPersistentRequesterClient(
          displayName: "RefineID Token",
          pair: persistentToken.pairRecord
        ).perform(
          .browserAuthentication(
            displayContext: Self.displayContext,
            keyProfile: RappOperationDriver.KeyProfile(persistentToken.profile),
            algorithm: algorithm,
            digest: request.digest
          )
        )
        guard case .signature(let receivedSignature) = response else {
          throw RappRequesterClientError.unexpectedResult
        }
        #if DEBUG
          Self.say("performRelaySign: received signature (\(receivedSignature.count) bytes)")
        #endif
        return receivedSignature
      } catch {
        let tkError = mapErrorToTKError(error)
        #if DEBUG
          let errDesc = String(describing: error)
          let elapsed = Self.millisecondsSince(started)
          let codeDesc = String(describing: tkError.code)
          Self.logger.notice(
            """
            [PersistentTokenDriver] rapp sign failed after \(elapsed) ms: \(errDesc, privacy: .public) \
            -> TKError(\(codeDesc, privacy: .public))
            """
          )
          ExtensionTrace.record(
            "rapp sign failed after \(Self.millisecondsSince(started)) ms: \(error) -> TKError(\(tkError.code))"
          )
          ExtensionTrace.flush()
        #endif
        throw tkError
      }
    }

    private func mapErrorToTKError(_ error: Error) -> TKError {
      if let tkError = error as? TKError {
        return tkError
      }
      if let clientError = error as? RappRequesterClientError {
        switch clientError {
        case .terminal(let reason):
          switch reason {
          case .userDenied, .cancelled, .cardRemovedBeforeTransmit, .requestExpired:
            return TKError(.canceledByUser)

          case .credentialRejected, .retryPolicyRefused:
            return TKError(.authenticationFailed)

          case .requestInvalidOrUnsupported, .cardCompletionAmbiguous, .none:
            return TKError(.corruptedData)
          }

        case .peerNotFound, .noActivePair, .noSelectedPair:
          return TKError(.tokenNotFound)

        case .protocolFailure, .transport, .timedOut, .unexpectedResult:
          return TKError(.communicationError)
        }
      }
      return TKError(.communicationError)
    }
  }

  override internal init() {
    super.init()
    delegate = self
  }

  internal func tokenDriver(
    _: TKTokenDriver,
    tokenFor configuration: TKToken.Configuration
  ) throws -> TKToken {
    try PersistentToken(tokenDriver: self, configuration: configuration)
  }
}
