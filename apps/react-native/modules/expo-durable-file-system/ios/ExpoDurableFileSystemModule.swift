import Darwin
import ExpoModulesCore
import Foundation

public final class ExpoDurableFileSystemModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ExpoDurableFileSystem")

    AsyncFunction("syncFile") { (value: String) throws in
      try self.syncPath(value, expectDirectory: false)
    }

    AsyncFunction("syncDirectory") { (value: String) throws in
      try self.syncPath(value, expectDirectory: true)
    }
  }

  private func syncPath(_ value: String, expectDirectory: Bool) throws {
    let url = try localURL(value)
    var isDirectory = ObjCBool(false)
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      throw syncError("Stable-storage target does not exist: \(value)", code: ENOENT)
    }
    guard isDirectory.boolValue == expectDirectory else {
      throw syncError("Stable-storage target has the wrong type: \(value)", code: EINVAL)
    }

    let flags = expectDirectory ? O_RDONLY : O_RDWR
    let descriptor = Darwin.open(url.path, flags)
    guard descriptor >= 0 else {
      throw syncError("Unable to open stable-storage target: \(value)", code: errno)
    }
    defer { Darwin.close(descriptor) }

    if Darwin.fcntl(descriptor, F_FULLFSYNC) == -1 && Darwin.fsync(descriptor) == -1 {
      throw syncError("Unable to sync stable-storage target: \(value)", code: errno)
    }
  }

  private func localURL(_ value: String) throws -> URL {
    if value.hasPrefix("file://") {
      guard let url = URL(string: value), url.isFileURL else {
        throw syncError("Invalid local file URI: \(value)", code: EINVAL)
      }
      return url.standardizedFileURL
    }
    guard value.hasPrefix("/") else {
      throw syncError("Only absolute local file paths can be synced: \(value)", code: EINVAL)
    }
    return URL(fileURLWithPath: value).standardizedFileURL
  }

  private func syncError(_ message: String, code: Int32) -> NSError {
    NSError(
      domain: "ExpoDurableFileSystem",
      code: Int(code),
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}
