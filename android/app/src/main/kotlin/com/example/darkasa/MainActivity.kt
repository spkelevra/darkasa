package com.example.darkasa

import android.content.ClipDescription
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaScannerConnection
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.darkasa/clipboard_image"
    private val MEDIA_CHANNEL = "com.example.darkasa/media_scanner"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Clipboard image channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getImageFromClipboard" -> {
                    try {
                        val clipboard = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
                        val clip = clipboard.primaryClip

                        if (clip == null || clip.itemCount == 0) {
                            result.success(null)
                            return@setMethodCallHandler
                        }

                        val item = clip.getItemAt(0)

                        // Case 1: Clipboard has a URI (content:// or file://) pointing to an image
                        if (item.uri != null) {
                            val uri = item.uri!!
                            val mimeType = contentResolver.getType(uri)
                            if (mimeType != null && mimeType.startsWith("image/")) {
                                val bitmap = android.graphics.BitmapFactory.decodeStream(
                                    contentResolver.openInputStream(uri)
                                )
                                if (bitmap != null) {
                                    val baos = ByteArrayOutputStream()
                                    // Choose format based on MIME type
                                    val compressFormat = when {
                                        mimeType.contains("jpeg") -> Bitmap.CompressFormat.JPEG
                                        else -> Bitmap.CompressFormat.PNG
                                    }
                                    bitmap.compress(compressFormat, 90, baos)
                                    bitmap.recycle()
                                    val bytes = baos.toByteArray()
                                    // Return as base64 string with format info
                                    val encoded = android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)
                                    val ext = when {
                                        mimeType.contains("jpeg") -> "jpg"
                                        mimeType.contains("gif") -> "gif"
                                        mimeType.contains("webp") -> "webp"
                                        else -> "png"
                                    }
                                    result.success(mapOf(
                                        "data" to encoded,
                                        "extension" to ext
                                    ))
                                    return@setMethodCallHandler
                                }
                            }
                        }

                        // Case 2: Clipboard has text that might be a file URI
                        val text = item.text?.toString()
                        if (text != null && (text.startsWith("file://") || text.startsWith("content://"))) {
                            try {
                                val uri = Uri.parse(text)
                                val bitmap = android.graphics.BitmapFactory.decodeStream(
                                    contentResolver.openInputStream(uri)
                                )
                                if (bitmap != null) {
                                    val baos = ByteArrayOutputStream()
                                    bitmap.compress(Bitmap.CompressFormat.PNG, 90, baos)
                                    bitmap.recycle()
                                    val encoded = android.util.Base64.encodeToString(baos.toByteArray(), android.util.Base64.NO_WRAP)
                                    result.success(mapOf(
                                        "data" to encoded,
                                        "extension" to "png"
                                    ))
                                    return@setMethodCallHandler
                                }
                            } catch (e: Exception) {
                                // Ignore - not a valid URI
                            }
                        }

                        // No image found
                        result.success(null)

                    } catch (e: Exception) {
                        result.error("CLIPBOARD_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Media scanner channel - notifies Gallery/Photos of new files
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFile" -> {
                    val filePath = call.argument<String>("path")
                    if (filePath != null) {
                        MediaScannerConnection.scanFile(
                            this,
                            arrayOf(filePath),
                            null,
                            object : MediaScannerConnection.OnScanCompletedListener {
                                override fun onScanCompleted(path: String?, uri: Uri?) {
                                    result.success(true)
                                }
                            }
                        )
                    } else {
                        result.error("INVALID_PATH", "No file path provided", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
