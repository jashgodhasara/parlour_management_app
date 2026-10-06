package com.example.parlour_management_app

import android.app.backup.BackupManager
import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val backupChannel = "parlour_management_app/backup"
    private val shareChannel = "parlour_management_app/share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backupChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dataChanged" -> {
                        BackupManager(this).dataChanged()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sharePdfToWhatsApp" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val fileName = call.argument<String>("fileName") ?: "bill.pdf"
                        val phone = call.argument<String>("phone")
                        val title = call.argument<String>("title") ?: "Bill PDF"
                        if (bytes == null || phone.isNullOrBlank()) {
                            result.error("missing_args", "PDF file or client phone number is missing.", null)
                            return@setMethodCallHandler
                        }

                        try {
                            sharePdfToWhatsApp(bytes, fileName, phone, title)
                            result.success(null)
                        } catch (e: ActivityNotFoundException) {
                            result.error("whatsapp_missing", "WhatsApp is not available on this phone.", null)
                        } catch (e: Exception) {
                            result.error("share_failed", e.message ?: "Could not send bill PDF.", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun sharePdfToWhatsApp(bytes: ByteArray, fileName: String, phone: String, title: String) {
        val safeFileName = fileName.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val file = File(cacheDir, safeFileName)
        file.writeBytes(bytes)

        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file
        )

        val jid = "${phone.replace("+", "")}@s.whatsapp.net"
        val packages = listOf("com.whatsapp", "com.whatsapp.w4b")
        var lastError: ActivityNotFoundException? = null

        for (packageName in packages) {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "application/pdf"
                setPackage(packageName)
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, title)
                putExtra("jid", jid)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            try {
                startActivity(intent)
                return
            } catch (e: ActivityNotFoundException) {
                lastError = e
            }
        }

        throw lastError ?: ActivityNotFoundException("WhatsApp is not installed.")
    }
}
