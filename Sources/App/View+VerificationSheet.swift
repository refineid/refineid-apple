// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import SwiftUI

  /// The sheet the Mac's Verify button opens.
  extension View {
    /// Shows `verification` in a sheet while there is one; closing the
    /// sheet ends it.
    internal func presentsVerification(
      _ verification: Binding<QueuedDocumentVerification?>
    ) -> some View {
      sheet(
        isPresented: Binding(
          get: { verification.wrappedValue != nil },
          set: { presented in
            if !presented { verification.wrappedValue = nil }
          }
        )
      ) {
        if let running = verification.wrappedValue {
          VerifyQueuedDocumentsView(verification: running)
        }
      }
    }
  }

#endif
