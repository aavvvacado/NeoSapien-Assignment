package com.example.neosapien_assignment

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ClipData
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.util.Log
import android.provider.OpenableColumns
import android.provider.MediaStore
import android.net.Uri
import android.net.wifi.WifiManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.UUID
import android.webkit.MimeTypeMap

class MainActivity : FlutterActivity() {
    private val channelName = "neosapien/native_bridge"
    private val pickFilesRequestCode = 10241
    private val incomingNotificationChannel = "neosapien_incoming_v2"
    private val headsUpChannelId = "neosapien_heads_up_v2"
    private val incomingNotificationId = 7702
    private val downloadSavedNotificationId = 7815
    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingLaunchTransferId: String? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    companion object {
        private const val REQ_POST_NOTIFICATIONS = 99102
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        pendingLaunchTransferId = intent?.getStringExtra("transfer_id")
        requestPostNotificationsIfNeeded()
    }

    private fun requestPostNotificationsIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQ_POST_NOTIFICATIONS,
        )
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingLaunchTransferId = intent.getStringExtra("transfer_id")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> handleSaveToDownloads(call, result)
                    "saveToDownloadsFromPath" -> handleSaveToDownloadsFromPath(call, result)
                    "pickFiles" -> handlePickFiles(result)
                    "shareFile" -> handleShareFile(call, result)
                    "getAvailableDownloadBytes" -> handleGetAvailableDownloadBytes(result)
                    "startForegroundTransfer" -> handleStartForegroundTransfer(call, result)
                    "updateForegroundTransfer" -> handleStartForegroundTransfer(call, result)
                    "stopForegroundTransfer" -> handleStopForegroundTransfer(result)
                    "enqueueTransferRecovery" -> handleEnqueueTransferRecovery(call, result)
                    "showIncomingTransferNotification" -> handleShowIncomingTransferNotification(call, result)
                    "showHeadsUpStatus" -> handleShowHeadsUpStatus(call, result)
                    "showDownloadSavedNotification" -> handleShowDownloadSavedNotification(call, result)
                    "openUriForView" -> handleOpenUriForView(call, result)
                    "consumeInitialTransferId" -> handleConsumeInitialTransferId(result)
                    "requestPostNotificationsPermission" -> handleRequestPostNotificationsPermission(result)
                    "acquireMulticastLock" -> handleAcquireMulticastLock(result)
                    "releaseMulticastLock" -> handleReleaseMulticastLock(result)
                    "openBatteryOptimizationSettings" -> handleOpenBatteryOptimizationSettings(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleConsumeInitialTransferId(result: MethodChannel.Result) {
        val id = pendingLaunchTransferId
        pendingLaunchTransferId = null
        result.success(id)
    }

    private fun handleRequestPostNotificationsPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        requestPostNotificationsIfNeeded()
        result.success(true)
    }

    private fun ensureMulticastLock(): WifiManager.MulticastLock {
        if (multicastLock != null) return multicastLock!!
        val wm = applicationContext.getSystemService(WifiManager::class.java)
        val lock = wm.createMulticastLock("neosapien_transfer")
        lock.setReferenceCounted(false)
        multicastLock = lock
        return lock
    }

    private fun handleAcquireMulticastLock(result: MethodChannel.Result) {
        try {
            ensureMulticastLock().acquire()
            result.success(true)
        } catch (e: Exception) {
            result.error("multicast_lock", e.message, null)
        }
    }

    private fun handleReleaseMulticastLock(result: MethodChannel.Result) {
        try {
            multicastLock?.let { if (it.isHeld) it.release() }
            result.success(true)
        } catch (e: Exception) {
            result.error("multicast_lock", e.message, null)
        }
    }

    private fun handleOpenBatteryOptimizationSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                intent.action = android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
            } else {
                intent.action = android.provider.Settings.ACTION_SETTINGS
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            result.success(true)
        } catch (t: Throwable) {
            result.error("battery_settings_failed", t.message, null)
        }
    }

    private fun ensureHeadsUpChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (manager.getNotificationChannel(headsUpChannelId) != null) return
        val channel = NotificationChannel(
            headsUpChannelId,
            "NeoSapien status",
            NotificationManager.IMPORTANCE_LOW, // Progress is quiet by default
        )
        channel.description = "Transfer sending and download progress"
        channel.enableVibration(false)
        manager.createNotificationChannel(channel)
    }

    private fun handleShowDownloadSavedNotification(call: MethodCall, result: MethodChannel.Result) {
        val fileName = call.argument<String>("fileName") ?: "Download"
        val openUriStr = call.argument<String>("openUriOrPath") ?: ""
        if (openUriStr.isBlank()) {
            result.error("bad_args", "openUriOrPath is required", null)
            return
        }
        try {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            ensureHeadsUpChannel(manager)
            val mime = guessMimeTypeForName(fileName)
            val uri = uriFromPathOrString(openUriStr, fileName)
            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                clipData = ClipData.newRawUri("", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val openPending = PendingIntent.getActivity(
                this,
                downloadSavedNotificationId,
                viewIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val notification = NotificationCompat.Builder(this, headsUpChannelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setColor(0xFF3ECF8E.toInt())
                .setContentTitle("Saved · $fileName")
                .setContentText("Tap to open")
                .setContentIntent(openPending)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .build()
            manager.notify(downloadSavedNotificationId, notification)
            result.success(true)
        } catch (t: Throwable) {
            result.error("download_saved_notification_failed", t.message, null)
        }
    }

    private fun handleOpenUriForView(call: MethodCall, result: MethodChannel.Result) {
        val pathOrUri = call.argument<String>("pathOrUri") ?: ""
        val fileName = call.argument<String>("fileName") ?: ""
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        
        try {
            val uri = when {
                pathOrUri.isNotBlank() ->
                    uriFromPathOrString(pathOrUri, fileName)
                fileName.isNotBlank() ->
                    resolveUriForFileName(fileName)
                        ?: throw IllegalStateException("File not found on device")
                else ->
                    throw IllegalStateException("Provide pathOrUri or fileName")
            }

            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                clipData = ClipData.newRawUri("", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(viewIntent)
            result.success(true)
        } catch (t: Throwable) {
            result.error("open_view_failed", t.message, null)
        }
    }

    /**
     * Finds a public MediaStore row by exact [MediaStore.MediaColumns.DISPLAY_NAME].
     * Images are often under [MediaStore.Images.Media], not [MediaStore.Files], so we query several collections.
     */
    private fun resolveUriForFileName(fileName: String): Uri? {
        Log.d("NeoSapien", "Resolving file discovery for: $fileName")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val collections = listOf(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                MediaStore.Files.getContentUri("external"),
            )
            for (collection in collections) {
                try {
                    val found = queryDisplayNameInCollection(resolver, collection, fileName)
                    if (found != null) {
                        Log.d("NeoSapien", "Found in ${collection}: $found")
                        return found
                    }
                } catch (e: Exception) {
                    Log.e("NeoSapien", "Query failed for $collection: ${e.message}")
                }
            }
        } 
        
        // Fallback: Check standard app-scoped downloads directory 
        val searchDirs = mutableListOf(
            cacheDir, 
            externalCacheDir, 
            getExternalFilesDir(null),
            getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
        )
        
        for (dir in searchDirs) {
            if (dir == null || !dir.exists()) continue
            Log.d("NeoSapien", "Searching app-scoped dir: ${dir.absolutePath}")
            val foundFile = dir.walkTopDown().find { it.isFile && it.name == fileName }
            if (foundFile != null && foundFile.exists()) {
                Log.d("NeoSapien", "Found file in fallback search: ${foundFile.absolutePath}")
                return FileProvider.getUriForFile(
                    this,
                    "${applicationContext.packageName}.fileprovider",
                    foundFile
                )
            }
        }

        Log.w("NeoSapien", "File not found anywhere: $fileName")
        return null
    }

    private fun queryDisplayNameInCollection(
        resolver: android.content.ContentResolver,
        collection: Uri,
        displayName: String,
    ): Uri? {
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} = ?"
        val selectionArgs = arrayOf(displayName)
        val sort = "${MediaStore.MediaColumns.DATE_MODIFIED} DESC"
        resolver.query(collection, projection, selection, selectionArgs, sort)?.use { cursor ->
            val idCol = cursor.getColumnIndex(MediaStore.MediaColumns._ID)
            if (idCol < 0) return null
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(idCol)
                return ContentUris.withAppendedId(collection, id)
            }
        }
        return null
    }

    private fun uriFromPathOrString(pathOrUri: String, displayNameFallback: String): Uri {
        if (pathOrUri.startsWith("content://")) {
            return Uri.parse(pathOrUri)
        }
        val file = File(pathOrUri)
        if (file.exists() && file.canRead()) {
            return FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                file
            )
        }
        if (displayNameFallback.isNotBlank()) {
            resolveUriForFileName(displayNameFallback)?.let { return it }
        }
        throw IllegalStateException("File not found on device")
    }

    private fun guessMimeTypeForName(fileName: String): String {
        val ext = MimeTypeMap.getFileExtensionFromUrl(fileName)
        if (ext != null && ext.isNotEmpty()) {
            val systemMime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext.lowercase())
            if (systemMime != null) return systemMime
        }

        val lower = fileName.lowercase()
        return when {
            lower.endsWith(".opus") -> "audio/opus"
            lower.endsWith(".pdf") -> "application/pdf"
            lower.endsWith(".png") -> "image/png"
            lower.endsWith(".jpg") || lower.endsWith(".jpeg") -> "image/jpeg"
            lower.endsWith(".gif") -> "image/gif"
            lower.endsWith(".webp") -> "image/webp"
            lower.endsWith(".heic") || lower.endsWith(".heif") -> "image/heif"
            lower.endsWith(".mp4") || lower.endsWith(".mov") || lower.endsWith(".mkv") || lower.endsWith(".webm") -> "video/mp4"
            lower.endsWith(".mp3") || lower.endsWith(".wav") || lower.endsWith(".m4a") -> "audio/mpeg"
            lower.endsWith(".txt") -> "text/plain"
            lower.endsWith(".zip") -> "application/zip"
            else -> "application/octet-stream"
        }
    }

    private fun handleShowHeadsUpStatus(call: MethodCall, result: MethodChannel.Result) {
        val title = call.argument<String>("title") ?: "NeoSapien"
        val body = call.argument<String>("body") ?: ""
        val notificationId = call.argument<Int>("notificationId") ?: 7801
        try {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            ensureHeadsUpChannel(manager)
            val launchIntent = Intent(this, MainActivity::class.java).apply {
                setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            val pendingIntent = PendingIntent.getActivity(
                this,
                notificationId,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val notification = NotificationCompat.Builder(this, headsUpChannelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setColor(0xFF3ECF8E.toInt())
                .setContentTitle(title)
                .setContentText(body)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .build()
            manager.notify(notificationId, notification)
            result.success(true)
        } catch (t: Throwable) {
            result.error("heads_up_failed", t.message, null)
        }
    }

    private fun handleShowIncomingTransferNotification(call: MethodCall, result: MethodChannel.Result) {
        val transferId = call.argument<String>("transferId")
        val senderPreview = call.argument<String>("senderPreview") ?: "Unknown sender"
        val fileCount = call.argument<Int>("fileCount") ?: 0
        if (transferId.isNullOrBlank()) {
            result.error("bad_args", "transferId is required", null)
            return
        }
        try {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val existing = manager.getNotificationChannel(incomingNotificationChannel)
                if (existing == null) {
                    val channel = NotificationChannel(
                        incomingNotificationChannel,
                        "NeoSapien Incoming",
                        NotificationManager.IMPORTANCE_HIGH,
                    )
                    channel.description = "Incoming transfer alerts"
                    channel.enableVibration(true)
                    manager.createNotificationChannel(channel)
                }
            }

            val launchIntent = Intent(this, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                putExtra("transfer_id", transferId)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            val pendingIntent = PendingIntent.getActivity(
                this,
                transferId.hashCode(),
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notification = NotificationCompat.Builder(this, incomingNotificationChannel)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setColor(0xFF3ECF8E.toInt())
                .setContentTitle("Incoming files")
                .setContentText("$fileCount file(s) from $senderPreview · tap to open Receive")
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .build()

            manager.notify(incomingNotificationId + transferId.hashCode(), notification)
            result.success(true)
        } catch (t: Throwable) {
            result.error("incoming_notification_failed", t.message, null)
        }
    }

    private fun handleEnqueueTransferRecovery(call: MethodCall, result: MethodChannel.Result) {
        val transferId = call.argument<String>("transferId")
        val direction = call.argument<String>("direction") ?: "unknown"
        if (transferId.isNullOrBlank()) {
            result.error("bad_args", "transferId is required", null)
            return
        }
        try {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()
            val input = Data.Builder()
                .putString(TransferRecoveryWorker.KEY_TRANSFER_ID, transferId)
                .putString(TransferRecoveryWorker.KEY_DIRECTION, direction)
                .build()
            val request = OneTimeWorkRequestBuilder<TransferRecoveryWorker>()
                .setInputData(input)
                .setConstraints(constraints)
                .build()
            WorkManager.getInstance(applicationContext).enqueueUniqueWork(
                "recover_$transferId",
                ExistingWorkPolicy.REPLACE,
                request
            )
            result.success(true)
        } catch (t: Throwable) {
            result.error("enqueue_recovery_failed", t.message, null)
        }
    }

    private fun handleStartForegroundTransfer(call: MethodCall, result: MethodChannel.Result) {
        val title = call.argument<String>("title") ?: "NeoSapien Transfer"
        val message = call.argument<String>("message") ?: "Transfer in progress"
        try {
            val serviceIntent = Intent(this, TransferForegroundService::class.java).apply {
                putExtra(TransferForegroundService.EXTRA_TITLE, title)
                putExtra(TransferForegroundService.EXTRA_MESSAGE, message)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            result.success(true)
        } catch (t: Throwable) {
            result.error("foreground_start_failed", t.message, null)
        }
    }

    private fun handleStopForegroundTransfer(result: MethodChannel.Result) {
        try {
            stopService(Intent(this, TransferForegroundService::class.java))
            result.success(true)
        } catch (t: Throwable) {
            result.error("foreground_stop_failed", t.message, null)
        }
    }

    private fun handleGetAvailableDownloadBytes(result: MethodChannel.Result) {
        try {
            val targetPath = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).absolutePath
            } else {
                @Suppress("DEPRECATION")
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).absolutePath
            }
            val statFs = StatFs(targetPath)
            val availableBytes = statFs.availableBytes
            result.success(availableBytes)
        } catch (t: Throwable) {
            result.error("space_failed", t.message, null)
        }
    }

    private fun handleSaveToDownloads(call: MethodCall, result: MethodChannel.Result) {
        val fileName = call.argument<String>("fileName")
        val bytes = call.argument<ByteArray>("bytes")
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"

        if (fileName.isNullOrBlank() || bytes == null) {
            result.error("bad_args", "fileName/bytes are required", null)
            return
        }

        try {
            val location = saveToDownloads(fileName, bytes, mimeType)
            result.success(location)
        } catch (t: Throwable) {
            result.error("save_failed", t.message, null)
        }
    }

    private fun handleSaveToDownloadsFromPath(call: MethodCall, result: MethodChannel.Result) {
        val fileName = call.argument<String>("fileName")
        val sourcePath = call.argument<String>("sourcePath")
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        if (fileName.isNullOrBlank() || sourcePath.isNullOrBlank()) {
            result.error("bad_args", "fileName/sourcePath are required", null)
            return
        }
        try {
            val srcFile = File(sourcePath)
            if (!srcFile.exists()) {
                result.error("missing_source", "Source file does not exist", null)
                return
            }
            val location = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val lower = fileName.lowercase()
                val (contentUri, relativePath) = when {
                    lower.endsWith(".jpg") || lower.endsWith(".jpeg") || lower.endsWith(".png") || lower.endsWith(".gif") || lower.endsWith(".webp") -> 
                        Pair(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, Environment.DIRECTORY_PICTURES + "/NeoSapien")
                    lower.endsWith(".mp4") || lower.endsWith(".mov") || lower.endsWith(".mkv") || lower.endsWith(".webm") -> 
                        Pair(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, Environment.DIRECTORY_MOVIES + "/NeoSapien")
                    lower.endsWith(".mp3") || lower.endsWith(".wav") || lower.endsWith(".m4a") || lower.endsWith(".aac") || lower.endsWith(".flac") -> 
                        Pair(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, Environment.DIRECTORY_MUSIC + "/NeoSapien")
                    else -> 
                        Pair(MediaStore.Downloads.EXTERNAL_CONTENT_URI, Environment.DIRECTORY_DOWNLOADS + "/NeoSapien")
                }

                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val resolver = applicationContext.contentResolver
                val uri = resolver.insert(contentUri, values)
                    ?: throw IllegalStateException("Unable to create MediaStore record")
                resolver.openOutputStream(uri)?.use { out ->
                    FileInputStream(srcFile).use { input ->
                        input.copyTo(out)
                    }
                    out.flush()
                } ?: throw IllegalStateException("Unable to open output stream")
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                uri.toString()
            } else {
                val downloads = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                if (downloads != null) {
                    val folder = File(downloads, "NeoSapien")
                    if (!folder.exists()) {
                        folder.mkdirs()
                    }
                    val target = File(folder, fileName)
                    FileInputStream(srcFile).use { input ->
                        FileOutputStream(target).use { output ->
                            input.copyTo(output)
                            output.flush()
                        }
                    }
                    target.absolutePath
                } else {
                    throw IllegalStateException("Unable to access external files directory")
                }
            }
            result.success(location)
        } catch (t: Throwable) {
            result.error("save_path_failed", t.message, null)
        }
    }

    private fun handlePickFiles(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("busy", "File picker is already active", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        startActivityForResult(intent, pickFilesRequestCode)
    }

    private fun handleShareFile(call: MethodCall, result: MethodChannel.Result) {
        val pathOrUri = call.argument<String>("pathOrUri") ?: ""
        val fileName = call.argument<String>("fileName") ?: "" // Added to support fallback
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        val title = call.argument<String>("title") ?: "Share file"

        try {
            val uri = when {
                pathOrUri.isNotBlank() ->
                    uriFromPathOrString(pathOrUri, fileName)
                fileName.isNotBlank() ->
                    resolveUriForFileName(fileName)
                        ?: throw IllegalStateException("File not found on device")
                else ->
                    throw IllegalStateException("Provide pathOrUri or fileName")
            }
            
            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newRawUri("", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(sendIntent, title))
            result.success(true)
        } catch (t: Throwable) {
            result.error("share_failed", t.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickFilesRequestCode) return

        val callback = pendingPickResult
        pendingPickResult = null
        if (callback == null) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            callback.success(emptyList<Map<String, Any>>())
            return
        }

        try {
            val pickedUris = mutableListOf<Uri>()
            data.clipData?.let { clip ->
                for (i in 0 until clip.itemCount) {
                    clip.getItemAt(i)?.uri?.let { pickedUris.add(it) }
                }
            }
            data.data?.let { pickedUris.add(it) }

            val files = pickedUris.mapNotNull { uri ->
                copyUriToCache(uri)
            }
            callback.success(files)
        } catch (t: Throwable) {
            callback.error("pick_failed", t.message, null)
        }
    }

    private fun copyUriToCache(uri: Uri): Map<String, Any>? {
        contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION
        )

        val cursor = contentResolver.query(uri, null, null, null, null)
        var name = "picked_${UUID.randomUUID()}"
        cursor?.use {
            val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (it.moveToFirst()) {
                if (nameIndex >= 0) {
                    name = it.getString(nameIndex) ?: name
                }
            }
        }

        val folder = File(cacheDir, "native_picker")
        if (!folder.exists()) folder.mkdirs()
        val outFile = File(folder, "${UUID.randomUUID()}_$name")
        contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(outFile).use { output ->
                input.copyTo(output)
            }
        } ?: return null

        val size = outFile.length()

        return mapOf(
            "path" to outFile.absolutePath,
            "name" to name,
            "size" to size.toInt(),
        )
    }

    private fun saveToDownloads(fileName: String, bytes: ByteArray, mimeType: String): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/NeoSapien")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }

            val resolver = applicationContext.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Unable to create MediaStore record")
            resolver.openOutputStream(uri)?.use { stream ->
                stream.write(bytes)
                stream.flush()
            } ?: throw IllegalStateException("Unable to open output stream")

            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            uri.toString()
        } else {
            val downloads = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            if (downloads != null) {
                val folder = File(downloads, "NeoSapien")
                if (!folder.exists()) {
                    folder.mkdirs()
                }
                val target = File(folder, fileName)
                FileOutputStream(target).use {
                    it.write(bytes)
                    it.flush()
                }
                target.absolutePath
            } else {
                throw IllegalStateException("Unable to access external files directory")
            }
        }
    }
}
