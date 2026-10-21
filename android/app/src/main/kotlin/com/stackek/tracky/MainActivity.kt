package com.stackek.tracky

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

class MainActivity : FlutterActivity() {
    private var pendingDirectoryResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STORAGE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickDirectory" -> pickDirectory(call.argument<String>("initialUri"), result)
                "writeFile" -> {
                    val uri = call.argument<String>("uri")
                    val fileName = call.argument<String>("fileName")
                    val mimeType =
                        call.argument<String>("mimeType") ?: "application/octet-stream"
                    val bytes = call.argument<ByteArray>("bytes")
                    if (uri == null || fileName == null || bytes == null) {
                        result.error("invalid_arguments", "Missing arguments.", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            writeFile(uri, fileName, mimeType, bytes)
                            runOnUiThread { result.success(fileName) }
                        } catch (error: Exception) {
                            runOnUiThread {
                                result.error(
                                    "write_failed",
                                    error.message ?: "Could not write the backup.",
                                    null,
                                )
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun pickDirectory(initialUri: String?, result: MethodChannel.Result) {
        if (pendingDirectoryResult != null) {
            result.error("already_active", "A folder picker is already open.", null)
            return
        }
        pendingDirectoryResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
            if (!initialUri.isNullOrEmpty()) {
                try {
                    putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(initialUri))
                } catch (_: Exception) {}
            }
        }
        startActivityForResult(intent, REQUEST_PICK_DIRECTORY)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_PICK_DIRECTORY) {
            val result = pendingDirectoryResult
            pendingDirectoryResult = null
            val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
            if (result == null) return
            if (uri == null) {
                result.success(null)
                return
            }
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            } catch (_: SecurityException) {}
            result.success(
                mapOf(
                    "uri" to uri.toString(),
                    "label" to directoryLabel(uri),
                ),
            )
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun directoryLabel(uri: Uri): String {
        val documentId = runCatching { DocumentsContract.getTreeDocumentId(uri) }.getOrNull()
            ?: return uri.toString()
        val parts = documentId.split(":", limit = 2)
        val volume = if (parts[0] == "primary") "Internal storage" else parts[0]
        val relative = parts.getOrNull(1).orEmpty()
        return if (relative.isEmpty()) volume else "$volume/$relative"
    }

    private fun writeFile(uri: String, fileName: String, mimeType: String, bytes: ByteArray) {
        val treeUri = Uri.parse(uri)
        val documentId = DocumentsContract.getTreeDocumentId(treeUri)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, documentId)
        var existing: Uri? = null
        contentResolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(1) == fileName) {
                    existing = DocumentsContract.buildDocumentUriUsingTree(
                        treeUri,
                        cursor.getString(0),
                    )
                    break
                }
            }
        }
        val destination = existing ?: DocumentsContract.createDocument(
            contentResolver,
            DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId),
            mimeType,
            fileName,
        ) ?: throw IOException("The selected folder cannot be written to.")
        contentResolver.openOutputStream(destination, "wt")?.use { it.write(bytes) }
            ?: throw IOException("The selected folder cannot be written to.")
    }

    companion object {
        private const val STORAGE_CHANNEL = "com.stackek.tracky/storage"
        private const val REQUEST_PICK_DIRECTORY = 4301
    }
}
