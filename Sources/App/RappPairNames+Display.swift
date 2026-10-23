// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

extension RappPairNames {
  /// The label to show for the pairing `pairID`, by ``label(name:model:)``,
  /// or a plain one when neither a name nor a model is stored, so the
  /// pairing is still shown and used.
  internal static func displayName(forPairID pairID: Data) -> String {
    label(name: name(forPairID: pairID), model: model(forPairID: pairID))
      ?? String(localized: "Paired device")
  }

  /// The peer's model when the peer gave no name or the model begins with
  /// the name, ignoring case, so a name such as "iPhone" yields to "iPhone
  /// 15 Pro Max"; otherwise the name.
  internal static func label(name: String?, model: String?) -> String? {
    guard let model else { return name }
    guard let name else { return model }
    let extendsName = model.range(of: name, options: [.anchored, .caseInsensitive]) != nil
    return extendsName ? model : name
  }
}
