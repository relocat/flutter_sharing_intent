// SPDX-License-Identifier: Apache-2.0
// Modified by Relocat (2026); see NOTICE.
package com.techind.flutter_sharing_intent

import android.app.SearchManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import android.webkit.URLUtil
import androidx.annotation.NonNull

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLConnection
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

private const val EVENTS_CHANNEL_MEDIA = "flutter_sharing_intent/events-sharing"

private const val THUMBNAIL_PNG_QUALITY = 100

/**
 **  Author - Bhagat Singh
 **  Contact - https://www.linkedin.com/in/bhagat-singh-79496a14b/
 **  Created On - 25/11/2022
 **  Purpose -  Created [FlutterSharingIntentPlugin] class to manage sharing intent
 */

class FlutterSharingIntentPlugin: FlutterPlugin, ActivityAware, MethodCallHandler,
  EventChannel.StreamHandler,
  PluginRegistry.NewIntentListener {
  private var TAG:String = javaClass.name

  /** To store initial & latest value when app is opened from background **/
  private var initialSharing: JSONArray? = null
  private var latestSharing: JSONArray? = null

  /// The MethodChannel that will the communication between Flutter and native Android
  private lateinit var channel : MethodChannel
  private lateinit var eventChannel: EventChannel

  private var eventSinkSharing: EventChannel.EventSink? = null

  private var binding: ActivityPluginBinding? = null
  private lateinit var applicationContext: Context

  /**
   * Background executor for intent handling work (FSI-24).
   *
   * [handleIntent] performs synchronous I/O — ContentResolver file copies for
   * content:// URIs, video thumbnail generation, and MediaMetadataRetriever
   * calls — all of which blocked the main thread when the Activity lifecycle
   * invoked the plugin. Large shared files at cold start could trigger ANR.
   * Work is marshalled onto this executor; channel emission is posted back to
   * the main thread via [mainHandler] because FlutterEventSink must be called
   * from the platform thread. The executor is shut down in
   * [onDetachedFromEngine].
   */
  private val backgroundExecutor: ExecutorService = Executors.newSingleThreadExecutor()
  private val mainHandler: Handler = Handler(Looper.getMainLooper())

  /// To sel channel & event stream
  private fun setupCallbackChannels(binaryMessenger: BinaryMessenger) {
    channel = MethodChannel(binaryMessenger, "flutter_sharing_intent")
    channel.setMethodCallHandler(this)

    eventChannel = EventChannel(binaryMessenger, EVENTS_CHANNEL_MEDIA)
    eventChannel.setStreamHandler(this)

  }

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    applicationContext = flutterPluginBinding.applicationContext
    setupCallbackChannels(flutterPluginBinding.binaryMessenger)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "getInitialSharing" -> {
         result.success(initialSharing?.toString())
          /// Clear cache data to send only once
          initialSharing = null
          latestSharing = null
      }
      "reset" -> {
        initialSharing = null
        latestSharing = null
        result.success(null)
      }
      "cleanup" -> {
        // Deletes only the plugin's own copies below cacheDir (shared files
        // and thumbnails); every other path is refused (FSI-104).
        val paths = call.argument<List<String>>("paths")
        if (paths == null) {
          result.error("INVALID_ARGUMENT", "cleanup requires paths: [String]", null)
          return
        }
        backgroundExecutor.execute {
          var removed = 0
          var isDone = false
          try {
            removed = MyFileDirectory.removeOwnedFiles(applicationContext.cacheDir, paths)
            isDone = true
          } catch (e: SecurityException) {
            Log.w(TAG, "cleanup failed: ${e.javaClass.simpleName}")
          } finally {
            // A reply is ALWAYS posted, so the Dart future never hangs.
            mainHandler.post {
              if (isDone) result.success(removed) else result.error("CLEANUP_FAILED", "cleanup failed", null)
            }
          }
        }
      }
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    initialSharing = null
    latestSharing = null
    eventChannel.setStreamHandler(null)
    backgroundExecutor.shutdown()
  }

  /**
   * Handles an incoming share intent.
   *
   * The computation — ContentResolver file copy, thumbnail generation,
   * MediaMetadataRetriever — is offloaded to [backgroundExecutor] to avoid
   * blocking the main thread (FSI-24). The resulting [JSONArray] (if any) is
   * published to [initialSharing]/[latestSharing] and emitted via
   * [eventSinkSharing] on the main thread via [mainHandler], because
   * FlutterEventSink must be called from the platform thread.
   */
  private fun handleIntent(intent: Intent, initial: Boolean) {
    val intentFlags = intent.getFlags()
    if ((intentFlags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return

    Log.w(TAG, "handleIntent")
    val tag: String = when {
      (intent.type?.startsWith("text") != true)
          && (intent.action == Intent.ACTION_SEND
          || intent.action == Intent.ACTION_SEND_MULTIPLE) -> "Image/Video"
      (intent.type == null || intent.type?.startsWith("text") == true)
          && (intent.action == Intent.ACTION_SEND
          || intent.action == Intent.ACTION_SEND_MULTIPLE) -> "text"
      intent.action == Intent.ACTION_VIEW -> "ACTION_VIEW"
      intent.action == Intent.ACTION_WEB_SEARCH -> "ACTION_WEB_SEARCH"
      else -> return
    }

    backgroundExecutor.execute {
      val value: JSONArray? = try {
        computeSharingPayload(intent)
      } catch (t: Throwable) {
        Log.e(TAG, "handleIntent failed: ${t.javaClass.simpleName}")
        return@execute
      }

      mainHandler.post {
        if (initial) initialSharing = value
        latestSharing = value
        Log.w(TAG, "$tag : handleIntent delivered ${value?.length() ?: 0} item(s)")
        eventSinkSharing?.success(value?.toString())
      }
    }
  }

  /**
   * Builds the [JSONArray] payload for a share intent. Runs on the background
   * executor — callers must not invoke this from the main thread because it
   * performs blocking I/O (see [getSharingUris]).
   */
  private fun computeSharingPayload(intent: Intent): JSONArray? {
    return when {
      (intent.type?.startsWith("text") != true)
          && (intent.action == Intent.ACTION_SEND
          || intent.action == Intent.ACTION_SEND_MULTIPLE) -> getSharingUris(intent)
      (intent.type == null || intent.type?.startsWith("text") == true)
          && (intent.action == Intent.ACTION_SEND
          || intent.action == Intent.ACTION_SEND_MULTIPLE) ->
        getSharingText(intent) ?: getSharingUris(intent)
      intent.action == Intent.ACTION_VIEW -> JSONArray().put(
        JSONObject()
          .put("value", intent.dataString)
          .put("type", MediaType.URL.ordinal)
      )
      intent.action == Intent.ACTION_WEB_SEARCH -> JSONArray().put(
        JSONObject()
          .put("value", intent.getStringExtra(SearchManager.QUERY))
          .put("type", MediaType.WEB_SEARCH.ordinal)
      )
      else -> null
    }
  }

  private fun getSharingUris(intent: Intent?): JSONArray? {
    if (intent == null) return null

    val uris: List<Uri> = when (intent.action) {
      Intent.ACTION_SEND -> listOfNotNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
      Intent.ACTION_SEND_MULTIPLE -> intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        ?: return null
      else -> return null
    }

    // All-or-nothing: if anything below fails, every copy and thumbnail made
    // for this intent is deleted before the payload is dropped (FSI-104).
    val paths = MyFileDirectory.getAbsolutePaths(applicationContext, uris)
    val thumbnails = mutableListOf<String>()
    return MyFileDirectory.withCleanup(cleanup = {
      MyFileDirectory.removeOwnedFiles(applicationContext.cacheDir, thumbnails)
      MyFileDirectory.deleteShareCopies(paths)
    }) {
      val items = JSONArray()
      for (path in paths) items.put(buildFileItem(path, thumbnails))
      if (intent.action == Intent.ACTION_SEND && items.length() == 0) null else items
    }
  }

  /**
   * Builds the payload entry for one copied file. A bad thumbnail or duration
   * never drops it, and every thumbnail is recorded in [createdThumbnails] the
   * moment it exists.
   */
  private fun buildFileItem(path: String, createdThumbnails: MutableList<String>): JSONObject {
    val type = getMediaType(path)
    val details = MyFileDirectory.extractMediaDetails(
      createdThumbnails,
      thumbnail = { getThumbnail(path, type) },
      duration = { getDuration(path, type) },
    )
    return JSONObject()
      .put("value", path)
      .put("type", type.ordinal)
      .put("thumbnail", details.thumbnail)
      .put("duration", details.duration)
  }

 private fun getSharingText(intent: Intent?): JSONArray? {
    if (intent == null) return null

    return when (intent.action) {
      Intent.ACTION_SEND -> {
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (text != null) {
          val type = getTypeForTextAndUrl(text)
          JSONArray().put(
            JSONObject()
              .put("value", text)
              .put("type", type)
          )
        } else null
      }
      Intent.ACTION_SEND_MULTIPLE -> {
        val textList = intent.getStringArrayListExtra(Intent.EXTRA_TEXT)

        val value = textList?.mapNotNull { text ->
          val path = text
            ?: return@mapNotNull null
          val type = getTypeForTextAndUrl(path)

          return@mapNotNull JSONObject()
            .put("value", path)
            .put("type", type)
        }?.toList()
        if (value != null) JSONArray(value) else null
      }
      else -> null
    }
  }

  // To get type for text and url only
  // It will return MediaType.URL.ordinal if text is valid url other will return MediaType.TEXT.ordinal
  fun getTypeForTextAndUrl( value: String?) : Int
  {
    return if (value == null || !URLUtil.isValidUrl(value)) MediaType.TEXT.ordinal else MediaType.URL.ordinal;
  }

  private fun getMediaType(path: String?): MediaType {
    val mimeType = URLConnection.guessContentTypeFromName(path)
    return when {
      mimeType?.startsWith("image") == true -> MediaType.IMAGE
      mimeType?.startsWith("video") == true -> MediaType.VIDEO
      mimeType?.startsWith("text") == true -> MediaType.TEXT
      mimeType?.startsWith("url") == true -> MediaType.URL
      mimeType?.startsWith("web_search") == true -> MediaType.WEB_SEARCH
      else -> MediaType.FILE
    }
  }

  /**
   * Generates a PNG thumbnail for a shared video and returns its cache path.
   *
   * Thumbnails are written to their own cache root under a random file name
   * ([MyFileDirectory.newThumbnailFile]), never next to the shared file and
   * never under a sender-chosen name. Stale thumbnails are pruned there
   * (FSI-23) before the new one is written.
   */
  private fun getThumbnail(path: String, type: MediaType): String? {
    if (type != MediaType.VIDEO) return null // get video thumbnail only

    val bitmap = ThumbnailUtils.createVideoThumbnail(path, MediaStore.Video.Thumbnails.MINI_KIND)
      ?: return null
    try {
      return MyFileDirectory.writeThumbnail(applicationContext.cacheDir) { out ->
        bitmap.compress(Bitmap.CompressFormat.PNG, THUMBNAIL_PNG_QUALITY, out)
      }
    } finally {
      bitmap.recycle()
    }
  }

  private fun getDuration(path: String, type: MediaType): Long? {
    if (type != MediaType.VIDEO) return null // get duration for video only
    val retriever = MediaMetadataRetriever()
    try {
      retriever.setDataSource(path)
      return retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
    } finally {
      retriever.release()
    }
  }

  enum class MediaType {
    TEXT, URL, IMAGE, VIDEO, FILE, WEB_SEARCH ;
  }

  override fun onNewIntent(intent: Intent): Boolean {
    handleIntent(intent, false)
    return false
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    this.binding = binding
    binding.addOnNewIntentListener(this)
    handleIntent(binding.activity.intent, true)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    binding?.removeOnNewIntentListener(this)
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    this.binding = binding
    binding.addOnNewIntentListener(this)
  }

  override fun onDetachedFromActivity() {
    binding?.removeOnNewIntentListener(this)
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    Log.d(TAG, "onListen")
    when (arguments) {
//      "sharing" -> eventSinkSharing = events
      "sharing" -> {
        eventSinkSharing = events


        latestSharing?.let {
          Log.d(TAG, "Cached sharing data present onListen: ${it.length()} item(s)")
//          eventSinkSharing?.success(it.toString())
        }
      }
    }
  }

  override fun onCancel(arguments: Any?) {
    Log.d(TAG, "onCancel")
    when (arguments) {
      "sharing" -> eventSinkSharing = null
    }
  }


}
