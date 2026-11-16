// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine) && os(macOS)
  import Darwin
  import Foundation

  /// Symlink-safe socket directory pinning, anti-squatter socket reclamation, and inode-checked unlinking.
  extension RappHeldSessionHandoff {
    /// Device and inode pair pinning a verified directory or bound socket entry.
    internal struct FileSystemIdentity: Sendable, Equatable {
      /// Filesystem device identifier (`st_dev`).
      internal let device: dev_t

      /// Inode number (`st_ino`).
      internal let inode: ino_t
    }

    /// Descriptor and filesystem identity of a newly bound listening socket.
    internal struct BoundSocket {
      /// Bound listening socket descriptor.
      internal let descriptor: Int32

      /// Device and inode recorded immediately after binding.
      internal let identity: FileSystemIdentity
    }

    private static let socketDirectoryName = "rh"
    private static let socketFileName = "s"
    private static let listenBacklog: Int32 = 8
    private static let probeTimeoutSeconds: TimeInterval = 0.25
    private static let directoryMode: mode_t = 0o700
    private static let socketMode: mode_t = 0o600

    /// Resolves the shared app-group socket location on macOS.
    internal static func defaultSocketURL() -> URL? {
      FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
        .appendingPathComponent(socketDirectoryName, isDirectory: true)
        .appendingPathComponent(socketFileName, isDirectory: false)
    }

    /// Creates and opens `directoryURL` with `O_DIRECTORY | O_NOFOLLOW`, setting `0700` via `fchmod`.
    internal static func preparePinnedDirectory(_ directoryURL: URL) -> FileSystemIdentity? {
      let path = directoryURL.path
      try? FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: Int(directoryMode)]
      )
      let descriptor = Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard descriptor != invalidDescriptor else { return nil }
      defer { _ = Darwin.close(descriptor) }
      var info = stat()
      guard
        Darwin.fstat(descriptor, &info) == 0,
        (info.st_mode & S_IFMT) == S_IFDIR,
        info.st_uid == Darwin.geteuid(),
        Darwin.fchmod(descriptor, directoryMode) == 0
      else {
        return nil
      }
      return FileSystemIdentity(device: info.st_dev, inode: info.st_ino)
    }

    /// Binds a listening socket inside a pinned directory, reclaiming stale or squatted paths safely.
    internal static func bindListenerSocket(
      at path: String,
      directoryPath: String,
      directoryIdentity: FileSystemIdentity,
      serverPolicy: PeerPolicy
    ) -> BoundSocket? {
      guard let address = makeSocketAddress(path: path) else { return nil }
      if let bound = attemptBindAndListen(
        address: address,
        path: path,
        directoryPath: directoryPath,
        directoryIdentity: directoryIdentity
      ) {
        return bound
      }
      guard
        verifyDirectoryIdentity(at: directoryPath, matches: directoryIdentity),
        !isOwnedByVerifiedApp(address: address, serverPolicy: serverPolicy)
      else {
        return nil
      }
      var existing = stat()
      if Darwin.lstat(path, &existing) == 0, (existing.st_mode & S_IFMT) == S_IFDIR {
        return nil
      }
      _ = Darwin.unlink(path)
      return attemptBindAndListen(
        address: address,
        path: path,
        directoryPath: directoryPath,
        directoryIdentity: directoryIdentity
      )
    }

    /// Unlinks `path` only when `lstat` confirms it is still the exact socket inode in `expected`.
    internal static func unlinkMatchingSocket(at path: String, expected: FileSystemIdentity) {
      var current = stat()
      guard
        Darwin.lstat(path, &current) == 0,
        (current.st_mode & S_IFMT) == S_IFSOCK,
        current.st_dev == expected.device,
        current.st_ino == expected.inode
      else {
        return
      }
      _ = Darwin.unlink(path)
    }

    private static func verifyDirectoryIdentity(
      at path: String,
      matches expected: FileSystemIdentity
    ) -> Bool {
      let descriptor = Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard descriptor != invalidDescriptor else { return false }
      defer { _ = Darwin.close(descriptor) }
      var info = stat()
      guard
        Darwin.fstat(descriptor, &info) == 0,
        (info.st_mode & S_IFMT) == S_IFDIR,
        info.st_uid == Darwin.geteuid()
      else {
        return false
      }
      return FileSystemIdentity(device: info.st_dev, inode: info.st_ino) == expected
    }

    private static func attemptBindAndListen(
      address: sockaddr_un,
      path: String,
      directoryPath: String,
      directoryIdentity: FileSystemIdentity
    ) -> BoundSocket? {
      guard verifyDirectoryIdentity(at: directoryPath, matches: directoryIdentity) else {
        return nil
      }
      let listenSocket = makeConfiguredSocket(readTimeout: nil, writeTimeout: nil)
      guard listenSocket != invalidDescriptor else { return nil }
      _ = Darwin.fchmod(listenSocket, socketMode)
      var mutable = address
      let length = socklen_t(MemoryLayout<sockaddr_un>.size)
      let bound = withUnsafePointer(to: &mutable) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPointer in
          Darwin.bind(listenSocket, sockPointer, length)
        }
      }
      guard bound == 0 else {
        _ = Darwin.close(listenSocket)
        return nil
      }
      _ = Darwin.lchmod(path, socketMode)
      var socketInfo = stat()
      guard
        verifyDirectoryIdentity(at: directoryPath, matches: directoryIdentity),
        Darwin.lstat(path, &socketInfo) == 0,
        (socketInfo.st_mode & S_IFMT) == S_IFSOCK,
        socketInfo.st_uid == Darwin.geteuid(),
        Darwin.listen(listenSocket, listenBacklog) == 0
      else {
        let cleanupIdentity = FileSystemIdentity(
          device: socketInfo.st_dev,
          inode: socketInfo.st_ino
        )
        _ = Darwin.close(listenSocket)
        unlinkMatchingSocket(at: path, expected: cleanupIdentity)
        return nil
      }
      let identity = FileSystemIdentity(device: socketInfo.st_dev, inode: socketInfo.st_ino)
      return BoundSocket(descriptor: listenSocket, identity: identity)
    }

    private static func isOwnedByVerifiedApp(
      address: sockaddr_un,
      serverPolicy: PeerPolicy
    ) -> Bool {
      let probe = makeConfiguredSocket(
        readTimeout: probeTimeoutSeconds,
        writeTimeout: probeTimeoutSeconds
      )
      guard probe != invalidDescriptor else { return false }
      defer { _ = Darwin.close(probe) }
      guard connectSocket(probe, to: address, timeoutSeconds: probeTimeoutSeconds) else {
        return false
      }
      return verifyPeer(of: probe, satisfying: serverPolicy)
    }
  }
#endif
