// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Recognises a file that is one CMS SignedData, as a `.p7m`, `.p7s`
/// or `.p7c` file holds (RFC 5652 section 3), without verifying it.
public enum CmsSignedDataFile {
  /// Whether `data` is one DER ContentInfo whose contentType is
  /// id-signedData.
  public static func isSignedData(_ data: Data) -> Bool {
    var outer = DerReader(data)
    guard
      let contentInfo = outer.next(), contentInfo.tag == DerValues.tagSequence,
      outer.isAtEnd
    else {
      return false
    }
    var info = DerReader(data, within: contentInfo)
    guard let type = info.next() else { return false }
    return info.data(of: type) == DerEncoder.objectIdentifier(SignOids.signedData)
  }
}
