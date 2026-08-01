package expo.modules.durablefilesystem

import android.net.Uri
import android.system.Os
import android.system.OsConstants
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.io.File

class ExpoDurableFileSystemModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("ExpoDurableFileSystem")

    AsyncFunction("syncFile") { value: String ->
      syncPath(value, expectDirectory = false)
    }

    AsyncFunction("syncDirectory") { value: String ->
      syncPath(value, expectDirectory = true)
    }
  }

  private fun syncPath(value: String, expectDirectory: Boolean) {
    val path = localPath(value)
    val target = File(path)
    require(target.exists()) { "Stable-storage target does not exist: $value" }
    require(target.isDirectory == expectDirectory) {
      "Stable-storage target has the wrong type: $value"
    }

    val flags = if (expectDirectory) {
      OsConstants.O_RDONLY or OsConstants.O_DIRECTORY
    } else {
      OsConstants.O_RDWR
    }
    val descriptor = Os.open(path, flags, 0)
    try {
      Os.fsync(descriptor)
    } finally {
      Os.close(descriptor)
    }
  }

  private fun localPath(value: String): String {
    val uri = Uri.parse(value)
    return when (uri.scheme) {
      null -> value
      "file" -> requireNotNull(uri.path) { "File URI has no path: $value" }
      else -> throw IllegalArgumentException("Only local file paths can be synced: $value")
    }
  }
}
