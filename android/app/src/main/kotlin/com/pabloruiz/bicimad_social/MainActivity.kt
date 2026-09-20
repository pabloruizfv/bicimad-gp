package com.pabloruiz.bicimad_social

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.content.pm.PackageInfo
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val installerChannel = "bicimad_gp/installer"
    private val installRequestCode = 8101
    private var pendingInstallResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installerChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "canInstallApk") {
                    result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls(),
                    )
                    return@setMethodCallHandler
                }
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingInstallResult != null) {
                    result.error("INSTALL_IN_PROGRESS", "An installation is already in progress", null)
                    return@setMethodCallHandler
                }
                val arguments = call.arguments as? Map<*, *>
                val path = arguments?.get("path") as? String
                val expectedVersion = arguments?.get("version") as? String
                if (path.isNullOrBlank()) {
                    result.error("INVALID_APK", "APK path is empty", null)
                    return@setMethodCallHandler
                }
                try {
                    val file = File(path).canonicalFile
                    if (!file.exists() || !file.isFile || !file.canonicalPath.startsWith(cacheDir.canonicalPath + File.separator)) {
                        result.error("MISSING_APK", "APK file does not exist", null)
                        return@setMethodCallHandler
                    }
                    val archive = packageManager.getPackageArchiveInfo(file.path, 0)
                    val installed = packageManager.getPackageInfo(packageName, 0)
                    if (archive == null || archive.packageName != packageName ||
                        archive.versionName != expectedVersion ||
                        versionCodeOf(archive) <= versionCodeOf(installed)
                    ) {
                        result.error("INVALID_APK", "The APK is not a newer version of this app", null)
                        return@setMethodCallHandler
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        !packageManager.canRequestPackageInstalls()
                    ) {
                        val settingsIntent = Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName"),
                        )
                        startActivity(settingsIntent)
                        result.success("permission_required")
                        return@setMethodCallHandler
                    }
                    val apkUri: Uri = FileProvider.getUriForFile(
                        this,
                        "$packageName.fileprovider",
                        file,
                    )
                    val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                        data = apkUri
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        putExtra(Intent.EXTRA_RETURN_RESULT, true)
                    }
                    pendingInstallResult = result
                    try {
                        startActivityForResult(intent, installRequestCode)
                    } catch (error: Exception) {
                        pendingInstallResult = null
                        throw error
                    }
                } catch (error: Exception) {
                    result.error("INSTALLER_ERROR", "Could not open Android installer", null)
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == installRequestCode) {
            pendingInstallResult?.success(
                if (resultCode == RESULT_OK) "installed" else "cancelled",
            )
            pendingInstallResult = null
        }
    }

    private fun versionCodeOf(info: PackageInfo): Long {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) return info.longVersionCode
        @Suppress("DEPRECATION")
        return info.versionCode.toLong()
    }
}
