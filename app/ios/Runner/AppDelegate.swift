import Flutter
import UIKit
import Security
import Darwin

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DermaireJournalKeys") {
      JournalKeyBridge.register(registrar)
    }
  }
}

// Device qualification and production activation remain separate gates.
private enum JournalKeyBridge {
  static let queue = DispatchQueue(label: "dermaire.journal.keys")
  static let service = "dermaire.journal.keys.v1"
  enum Failure: String, Error { case unavailable, syncOpen, syncCommit, fileProtectionMismatch }
  static func sync(_ url: URL) throws {
    let fd = Darwin.open(url.path, O_RDONLY)
    guard fd >= 0 else { throw Failure.syncOpen }
    defer { Darwin.close(fd) }
    guard Darwin.fsync(fd) == 0 else { throw Failure.syncCommit }
  }
  static func register(_ registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "dermaire/journal-keys-v1", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      queue.async {
        do {
          guard let arguments = call.arguments as? [String: Any],
                let ns = arguments["namespace"] as? String,
                ns.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw Failure.unavailable
          }
          let fm = FileManager.default
          var root = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("journal-v1", isDirectory: true)
          try fm.createDirectory(at: root, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
          var values = URLResourceValues(); values.isExcludedFromBackup = true
          try root.setResourceValues(values)
          try sync(root.deletingLastPathComponent())
          let fence = root.appendingPathComponent(ns + ".fence")
          var dir = root.appendingPathComponent(ns, isDirectory: true)
          let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: ns,
            kSecAttrSynchronizable as String: false]
          let output: Any?
          switch call.method {
          case "epoch":
            let epoch = root.appendingPathComponent("installation.epoch")
            if !fm.fileExists(atPath: epoch.path) {
              guard try fm.contentsOfDirectory(atPath: root.path).isEmpty else { throw Failure.unavailable }
              var bytes = [UInt8](repeating: 0, count: 32)
              guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Failure.unavailable }
              try Data(bytes).write(to: epoch, options: [.atomic, .completeFileProtection])
              try sync(epoch); try sync(root)
            }
            let data = try Data(contentsOf: epoch)
            guard data.count == 32 else { throw Failure.unavailable }
            output = FlutterStandardTypedData(bytes: data)
          case "protectFiles":
            guard !fm.fileExists(atPath: fence.path) else { throw Failure.unavailable }
            for file in try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
              try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path)
              var protected = file
              try protected.setResourceValues(values)
              let attrs = try fm.attributesOfItem(atPath: file.path)
              let protection = (attrs[.protectionKey] as? FileProtectionType)?.rawValue ?? (attrs[.protectionKey] as? String)
              guard protection == FileProtectionType.complete.rawValue else { throw Failure.fileProtectionMismatch }
              try sync(file)
            }
            try sync(dir); output = nil
          case "eraseFiles":
            guard fm.fileExists(atPath: fence.path) else { throw Failure.unavailable }
            if fm.fileExists(atPath: dir.path) { try fm.removeItem(at: dir) }
            try sync(root); output = nil // Retain fence permanently.
          case "fence":
            try Data([1]).write(to: fence, options: [.atomic, .completeFileProtection])
            try sync(fence); try sync(root); output = nil
          case "destroyKey":
            guard fm.fileExists(atPath: fence.path) else { throw Failure.unavailable }
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.unavailable }
            output = nil
          case "directory", "loadKey", "createKey":
            guard !fm.fileExists(atPath: fence.path) else { throw Failure.unavailable }
            try fm.createDirectory(at: dir, withIntermediateDirectories: true,
              attributes: [.protectionKey: FileProtectionType.complete])
            try dir.setResourceValues(values); try sync(root)
            if call.method == "directory" { output = dir.path } else {
              var read = query
              read[kSecReturnData as String] = true
              read[kSecMatchLimit as String] = kSecMatchLimitOne
              var existing: CFTypeRef?
              let status = SecItemCopyMatching(read as CFDictionary, &existing)
              var data: Data
              if status == errSecSuccess, let found = existing as? Data {
                guard call.method == "loadKey" else { throw Failure.unavailable }
                data = found
              }
              else if status == errSecItemNotFound && call.method == "createKey" {
                guard try fm.contentsOfDirectory(atPath: dir.path).isEmpty else { throw Failure.unavailable }
                var bytes = [UInt8](repeating: 0, count: 32)
                guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Failure.unavailable }
                data = Data(bytes); bytes = [UInt8](repeating: 0, count: 32)
                var insert = query
                insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                insert[kSecValueData as String] = data
                guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw Failure.unavailable }
              } else { throw Failure.unavailable }
              guard data.count == 32 else { throw Failure.unavailable }
              output = FlutterStandardTypedData(bytes: data)
            }
          default: throw Failure.unavailable
          }
          DispatchQueue.main.async { result(output) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "journal_key_unavailable", message: "Protected journal key unavailable", details: ["reason": (error as? Failure)?.rawValue ?? "filesystem-\((error as NSError).code)"])) }
        }
      }
    }
  }
}
