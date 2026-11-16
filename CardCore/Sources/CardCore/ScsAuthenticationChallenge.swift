// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The origin-bound challenge rule for authentication-key signs.
///
/// The authentication certificate is an authentication-purpose key,
/// so the SCS refuses to sign arbitrary bytes with it: the content must
/// be `origin;nonce`, where `origin` matches the request's `Origin`
/// header byte for byte and `nonce` is at least 64 octets of caller
/// randomness containing no `;` separator (DVV SCS specification v1.3
/// §2.1, §3.7). Forbidding `;` in `nonce` also keeps the plain JSON
/// `/sign` path from forging a three-field `origin;nonce;serverKey`
/// transaction challenge.
public enum ScsAuthenticationChallenge {
  /// Why `content` is not an acceptable challenge, or nil when it is.
  public static func refusal(content: Data, origin: String?) -> String? {
    guard let origin else {
      return "missing Origin header"
    }
    if let originRefusal = ScsOriginPolicy.refusal(forPresentOrigin: origin) {
      return originRefusal
    }
    guard let text = String(data: content, encoding: .utf8) else {
      return "challenge must be UTF-8 (origin;nonce)"
    }
    guard let separator = text.firstIndex(of: ";") else {
      return "challenge missing ; separator (expected origin;nonce)"
    }
    let challengeOrigin = String(text[text.startIndex..<separator])
    let nonce = text[text.index(after: separator)...]
    guard challengeOrigin == origin else {
      return "challenge origin does not match request Origin"
    }
    guard !nonce.contains(";") else {
      return "challenge nonce must not contain ;"
    }
    guard nonce.utf8.count >= ScsValues.nonceMinimumLength else {
      return "challenge nonce too short (minimum 64 octets)"
    }
    return nil
  }
}
