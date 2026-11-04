package com.globalspeed.globalspeed_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 应用内更新需要的原生能力：ABI 列表、打开链接、安装 APK。
 * 下载本身放在 Dart 侧（多线程分段），这里只负责「装上」。
 */
class Updater(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "globalspeed/updater"
    }

    private var channel: MethodChannel? = null

    fun attach(messenger: BinaryMessenger) {
        val ch = MethodChannel(messenger, CHANNEL)
        ch.setMethodCallHandler(this)
        channel = ch
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "info" -> result.success(info())
            "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
            "openUrl" -> result.success(openUrl(call.argument<String>("url").orEmpty()))
            "install" -> result.success(install(call.argument<String>("path").orEmpty()))
            "installSettings" -> result.success(openInstallSettings())
            else -> result.notImplemented()
        }
    }

    private fun canInstall(): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    } catch (_: Throwable) {
        true
    }

    private fun info(): Map<String, Any?> = mapOf(
        "installAllowed" to canInstall(),
        "abis" to Build.SUPPORTED_ABIS.toList(),
        "sdk" to Build.VERSION.SDK_INT,
    )

    private fun openUrl(url: String): Boolean {
        if (url.isEmpty()) return false
        return try {
            activity.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun openInstallSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${activity.packageName}"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun install(path: String): Boolean {
        val file = File(path)
        if (!file.exists() || file.length() <= 0) return false
        return try {
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.fileprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }
}
