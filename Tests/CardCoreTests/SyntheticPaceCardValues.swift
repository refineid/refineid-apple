// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The wire values `SyntheticPaceCard` answers with, transcribed here
/// independently of the module's own copies.
internal enum SyntheticPaceCardValues {
  /// Normal processing.
  internal static let successHex: String = "9000"

  /// `6300`: authentication failed, no counter.
  internal static let authenticationFailedHex: String = "6300"

  /// `6A80`: incorrect data.
  internal static let incorrectDataHex: String = "6A80"

  /// SELECT.
  internal static let select: UInt8 = 0xA4

  /// READ BINARY.
  internal static let readBinary: UInt8 = 0xB0

  /// MANAGE SECURITY ENVIRONMENT.
  internal static let manageSecurityEnvironment: UInt8 = 0x22

  /// GENERAL AUTHENTICATE.
  internal static let generalAuthenticate: UInt8 = 0x86

  /// Tag `7C`, dynamic authentication data.
  internal static let dynamicAuthenticationDataTag: UInt8 = 0x7C

  /// Tag `80`: the mechanism in MSE:Set AT, the encrypted nonce in `7C`.
  internal static let mechanismOrNonceTag: UInt8 = 0x80

  /// Tag `81` inside `7C`: the terminal's mapping data.
  internal static let mappingDataTerminalTag: UInt8 = 0x81

  /// Tag `82` inside `7C`: the card's mapping data.
  internal static let mappingDataCardTag: UInt8 = 0x82

  /// Tag `83`: the password reference in MSE:Set AT, the terminal's
  /// ephemeral public key in `7C`.
  internal static let passwordOrTerminalKeyTag: UInt8 = 0x83

  /// Tag `84`: the domain parameter in MSE:Set AT, the card's ephemeral
  /// public key in `7C`.
  internal static let domainOrCardKeyTag: UInt8 = 0x84

  /// Tag `85` inside `7C`: the terminal's authentication token.
  internal static let authenticationTokenTerminalTag: UInt8 = 0x85

  /// Tag `86` inside `7C`: the card's authentication token.
  internal static let authenticationTokenCardTag: UInt8 = 0x86

  /// Tag `06`, OBJECT IDENTIFIER.
  internal static let objectIdentifierTag: UInt8 = 0x06

  /// The first byte of tag `7F49`.
  internal static let publicKeyTemplateFirstByte: UInt8 = 0x7F

  /// The second byte of tag `7F49`.
  internal static let publicKeyTemplateSecondByte: UInt8 = 0x49

  /// Tag `86` inside `7F49`: the point the token covers.
  internal static let publicKeyTemplatePointTag: UInt8 = 0x86

  /// `id-PACE-ECDH-GM-AES-CBC-CMAC-256` under the BSI branch
  /// `0.4.0.127.0.7.2.2.4.2.4`, transcribed here independently of the
  /// module's own copy.
  internal static let protocolOidHex: String = "04007F00070202040204"

  /// Where an APDU's instruction byte sits.
  internal static let instructionOffset: Int = 1

  /// Where an APDU's P1 sits.
  internal static let parameterOneOffset: Int = 2

  /// Where an APDU's P2 sits.
  internal static let parameterTwoOffset: Int = 3

  /// Where a short-form command's Lc byte sits.
  internal static let lengthOffset: Int = 4

  /// Where a short-form command's body starts.
  internal static let bodyOffset: Int = 5

  /// A short `Le` of zero asks for this many bytes.
  internal static let maximumShortLength: Int = 256

  /// The bits in one octet, the shift of Horner's rule over points.
  internal static let bitsPerOctet: Int = 8

  /// The Doc 9303 key derivation counter for Kenc.
  internal static let encryptionCounter: UInt32 = 1

  /// The Doc 9303 key derivation counter for Kmac.
  internal static let macCounter: UInt32 = 2

  /// The Doc 9303 key derivation counter for the password key.
  internal static let passwordCounter: UInt32 = 3
}
