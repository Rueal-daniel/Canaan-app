package com.example.canaan_app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channel = "canaan_app/update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getVersionCode" -> {
                    try {
                        val pm = applicationContext.packageManager
                        val pkg = applicationContext.packageName
                        val code = if (Build.VERSION.SDK_INT >= 28) {
                            pm.getPackageInfo(pkg, 0)
                                .longVersionCode.toInt()
                        } else {
                            @Suppress("DEPRECATION")
                            pm.getPackageInfo(pkg, 0).versionCode
                        }
                        result.success(code)
                    } catch (e: Exception) {
                        result.error("UNAVAILABLE", e.message, null)
                    }
                }
                "getVersionName" -> {
                    try {
                        val pm = applicationContext.packageManager
                        val pkg = applicationContext.packageName
                        @Suppress("DEPRECATION")
                        val name = pm.getPackageInfo(pkg, 0).versionName
                        result.success(name ?: "")
                    } catch (e: Exception) {
                        result.error("UNAVAILABLE", e.message, null)
                    }
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("BAD_PATH", "Empty APK path", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        val authority =
                            "${applicationContext.packageName}.fileprovider"
                        val uri = FileProvider.getUriForFile(
                            applicationContext,
                            authority,
                            file
                        )
                        val intent =
                            Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(
                                    uri,
                                    "application/vnd.android.package-archive"
                                )
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                        applicationContext.startActivity(intent)
                        result.success("ok")
                    } catch (e: ActivityNotFoundException) {
                        result.error("NO_HANDLER", e.message, null)
                    } catch (e: SecurityException) {
                        result.error("BLOCKED", e.message, null)
                    } catch (e: IllegalArgumentException) {
                        result.error("BAD_FILE", e.message, null)
                    } catch (e: Exception) {
                        result.error("FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
