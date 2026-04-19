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
import java.io.File
import java.io.FileOutputStream
import java.net.URLConnection
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

private const val EVENTS_CHANNEL_MEDIA = "flutter_sharing_intent/events-sharing"

private const val THUMBNAIL_TTL_MILLIS = 7L * 24L * 60L * 60L * 1000L

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

    Log.w(TAG, "handleIntent ==>> ${intent.action}, ${intent.type}")
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
        Log.e(TAG, "handleIntent failed", t)
        return@execute
      }

      mainHandler.post {
        if (initial) initialSharing = value
        latestSharing = value
        Log.w(TAG, "$tag : handleIntent ==>> $value")
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

    return when (intent.action) {
      Intent.ACTION_SEND -> {
        val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        val path = uri?.let{ MyFileDirectory.getAbsolutePath(applicationContext, it) }
        if (path != null) {
          val type = getMediaType(path)
          val thumbnail = getThumbnail(path, type)
          val duration = getDuration(path, type)

          JSONArray().put(
            JSONObject()
              .put("value", path)
              .put("type", type.ordinal)
              .put("thumbnail", thumbnail)
              .put("duration", duration)
          )
        } else null
      }
      Intent.ACTION_SEND_MULTIPLE -> {
        val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        val value = uris?.mapNotNull { uri ->
          val path = MyFileDirectory.getAbsolutePath(applicationContext, uri)
            ?: return@mapNotNull null
          val type = getMediaType(path)
          val thumbnail = getThumbnail(path, type)
          val duration = getDuration(path, type)
          return@mapNotNull JSONObject()
            .put("value", path)
            .put("type", type.ordinal)
            .put("thumbnail", thumbnail)
            .put("duration", duration)
        }?.toList()
        if (value != null) JSONArray(value) else null
      }
      else -> null
    }
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
   * Thumbnails are written to [applicationContext]'s cacheDir keyed by the source
   * filename. To prevent unbounded growth (FSI-23), this function prunes any
   * plugin-generated `*.png` entries older than [THUMBNAIL_TTL_MILLIS] before
   * writing the new thumbnail. The prune is best-effort — failures are logged
   * and do not abort thumbnail generation.
   */
  private fun getThumbnail(path: String, type: MediaType): String? {
    if (type != MediaType.VIDEO) return null // get video thumbnail only

    pruneStaleThumbnails(applicationContext.cacheDir)

    val videoFile = File(path)
    val targetFile = File(applicationContext.cacheDir, "${videoFile.name}.png")
    val bitmap = ThumbnailUtils.createVideoThumbnail(path, MediaStore.Video.Thumbnails.MINI_KIND)
      ?: return null
    FileOutputStream(targetFile).use { out ->
      bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
    }
    bitmap.recycle()
    return targetFile.path
  }

  // Shared with getThumbnail — evicts stale plugin-generated thumbnails
  // to prevent unbounded cacheDir growth (FSI-23).
  private fun pruneStaleThumbnails(cacheDir: File) {
    val cutoff = System.currentTimeMillis() - THUMBNAIL_TTL_MILLIS
    try {
      cacheDir.listFiles { f -> f.isFile && f.name.endsWith(".png") }
        ?.forEach { file ->
          if (file.lastModified() < cutoff) {
            file.delete()
          }
        }
    } catch (e: SecurityException) {
      Log.w("FlutterSharingIntent", "Thumbnail prune failed: ${e.message}")
    }
  }

  private fun getDuration(path: String, type: MediaType): Long? {
    if (type != MediaType.VIDEO) return null // get duration for video only
    val retriever = MediaMetadataRetriever()
    retriever.setDataSource(path)
    val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
    retriever.release()
    return duration
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
    Log.d(TAG,"onListen ==>> $arguments, $events")
    when (arguments) {
//      "sharing" -> eventSinkSharing = events
      "sharing" -> {
        eventSinkSharing = events


        latestSharing?.let {
          Log.d(TAG, "Sending cached sharing data onListen: $it")
//          eventSinkSharing?.success(it.toString())
        }
      }
    }
  }

  override fun onCancel(arguments: Any?) {
    Log.d(TAG,"onCancel ==>> $arguments")
    when (arguments) {
      "sharing" -> eventSinkSharing = null
    }
  }


}
