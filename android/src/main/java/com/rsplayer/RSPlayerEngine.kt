package com.rsplayer

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaSession
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.WritableMap

object RSPlayerEngine {
  private const val PROGRESS_INTERVAL_MS = 250L
  private const val TAG = "RSPlayer"

  private val mainHandler = Handler(Looper.getMainLooper())
  private var appContext: Context? = null
  private var eventSink: ((WritableMap) -> Unit)? = null
  private var mediaSession: MediaSession? = null
  private var player: ExoPlayer? = null
  private var cuePlayer: ExoPlayer? = null
  private var cuePromise: Promise? = null
  private var progressRunnable: Runnable? = null
  private var showSystemControls = true

  private val playerListener =
    object : Player.Listener {
      override fun onPlaybackStateChanged(playbackState: Int) {
        when (playbackState) {
          Player.STATE_BUFFERING -> emitState("buffering")
          Player.STATE_READY -> {
            emitLoad()
            emitState(if (player?.isPlaying == true) "playing" else "paused")
          }
          Player.STATE_ENDED -> {
            emitProgress()
            emitEvent("ended")
          }
          Player.STATE_IDLE -> emitState("idle")
        }
      }

      override fun onIsPlayingChanged(isPlaying: Boolean) {
        emitState(if (isPlaying) "playing" else "paused")
      }

      override fun onPlayerError(error: PlaybackException) {
        emitError(error.message ?: "Audio playback error")
      }
    }

  private val cuePlayerListener =
    object : Player.Listener {
      override fun onPlaybackStateChanged(playbackState: Int) {
        if (playbackState == Player.STATE_ENDED) {
          resolveCueAndRelease()
        }
      }

      override fun onPlayerError(error: PlaybackException) {
        rejectCueAndRelease(error.message ?: "Cue playback error", error)
      }
    }

  fun attach(context: Context, sink: ((WritableMap) -> Unit)? = null) {
    appContext = context.applicationContext
    if (sink != null) {
      eventSink = sink
    }
  }

  fun clearEventSink() {
    eventSink = null
  }

  fun getOrCreateMediaSession(context: Context): MediaSession {
    attach(context)
    showSystemControls = true
    mediaSession?.let { return it }

    Log.d(TAG, "creating media session")
    val builder = MediaSession.Builder(context, getOrCreatePlayer(context))
    buildSessionActivity(context)?.let { builder.setSessionActivity(it) }

    return builder.build().also { mediaSession = it }
  }

  fun load(context: Context, options: ReadableMap) {
    attach(context)
    val autoPlay = options.getBooleanOrDefault("autoPlay", false)
    showSystemControls = options.getBooleanOrDefault("showSystemControls", true)
    if (showSystemControls && autoPlay) {
      startPlaybackService(context)
    } else if (!showSystemControls) {
      hideSystemControls(context)
    }

    val uri = options.getString("uri")?.trim()
    if (uri.isNullOrEmpty()) {
      throw IllegalArgumentException("Audio URI is empty")
    }

    Log.d(
      TAG,
      "load autoPlay=$autoPlay showSystemControls=$showSystemControls title=${options.getStringOrNull("title") ?: "unknown"}"
    )
    val mediaItem =
      MediaItem.Builder()
        .setUri(Uri.parse(uri))
        .setMediaMetadata(buildMetadata(options))
        .build()
    val mediaSourceFactory = DefaultMediaSourceFactory(buildDataSourceFactory(context, options))
    val mediaSource = mediaSourceFactory.createMediaSource(mediaItem)
    val activePlayer = getOrCreatePlayer(context)

    activePlayer.repeatMode =
      if (options.getBooleanOrDefault("loop", false)) {
        Player.REPEAT_MODE_ONE
      } else {
        Player.REPEAT_MODE_OFF
    }
    activePlayer.volume =
      options.getDoubleOrDefault("volume", 1.0).coerceIn(0.0, 1.0).toFloat()
    activePlayer.setMediaSource(mediaSource)
    activePlayer.playWhenReady = autoPlay
    activePlayer.prepare()
    startProgressUpdates()
    emitState("loading")
  }

  fun play(context: Context) {
    attach(context)
    Log.d(TAG, "play")
    if (showSystemControls) {
      startPlaybackService(context)
    }
    getOrCreatePlayer(context).play()
    startProgressUpdates()
  }

  fun playCue(context: Context, options: ReadableMap, promise: Promise) {
    attach(context)
    Log.d(TAG, "play cue")

    val uri = options.getString("uri")?.trim()
    if (uri.isNullOrEmpty()) {
      throw IllegalArgumentException("Cue URI is empty")
    }

    stopCue()

    val mediaItem =
      MediaItem.Builder()
        .setUri(Uri.parse(uri))
        .build()
    val mediaSourceFactory = DefaultMediaSourceFactory(buildDataSourceFactory(context, options))
    val mediaSource = mediaSourceFactory.createMediaSource(mediaItem)
    val activeCuePlayer = createCuePlayer(context)

    cuePromise = promise
    activeCuePlayer.volume =
      options.getDoubleOrDefault("volume", 1.0).coerceIn(0.0, 1.0).toFloat()
    activeCuePlayer.setMediaSource(mediaSource)
    activeCuePlayer.playWhenReady = true
    activeCuePlayer.prepare()
  }

  fun pause() {
    Log.d(TAG, "pause")
    player?.pause()
    emitState("paused")
    emitProgress()
  }

  fun stop() {
    Log.d(TAG, "stop")
    player?.pause()
    player?.seekTo(0)
    emitState("paused")
    emitProgress()
  }

  fun stopCue() {
    Log.d(TAG, "stop cue")
    resolveCueAndRelease()
  }

  fun reset(context: Context) {
    Log.d(TAG, "reset")
    release()
    emitState("idle")
    context.stopService(Intent(context, RSPlayerPlaybackService::class.java))
  }

  fun seekTo(seconds: Double) {
    player?.seekTo((seconds.coerceAtLeast(0.0) * 1000).toLong())
    emitProgress()
  }

  fun setVolume(volume: Double) {
    player?.volume = volume.coerceIn(0.0, 1.0).toFloat()
  }

  fun setLoop(loop: Boolean) {
    player?.repeatMode = if (loop) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
  }

  fun getState(): WritableMap =
    Arguments.createMap().apply {
      val activePlayer = player
      putString("state", currentState(activePlayer))
      putDouble("position", seconds(activePlayer?.currentPosition ?: 0))
      putDouble("duration", seconds(activePlayer?.duration ?: C.TIME_UNSET))
      putDouble("buffered", seconds(activePlayer?.bufferedPosition ?: 0))
    }

  fun release() {
    Log.d(TAG, "release")
    stopProgressUpdates()
    resolveCueAndRelease()
    releaseMediaSession()
    player?.removeListener(playerListener)
    player?.release()
    player = null
  }

  fun onPlaybackServiceDestroyed() {
    Log.d(TAG, "service destroyed")
    mediaSession = null
  }

  private fun startPlaybackService(context: Context) {
    Log.d(TAG, "start playback service")
    ContextCompat.startForegroundService(
      context.applicationContext,
      Intent(context, RSPlayerPlaybackService::class.java)
    )
  }

  private fun hideSystemControls(context: Context) {
    Log.d(TAG, "hide system controls")
    releaseMediaSession()
    context.applicationContext.stopService(Intent(context, RSPlayerPlaybackService::class.java))
  }

  private fun releaseMediaSession() {
    mediaSession?.release()
    mediaSession = null
  }

  private fun buildSessionActivity(context: Context): PendingIntent? {
    val launchIntent =
      context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
        addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
      } ?: return null

    return PendingIntent.getActivity(
      context,
      10080,
      launchIntent,
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    )
  }

  private fun getOrCreatePlayer(context: Context): ExoPlayer {
    player?.let { return it }

    val audioAttributes =
      AudioAttributes.Builder()
        .setContentType(C.AUDIO_CONTENT_TYPE_SPEECH)
        .setUsage(C.USAGE_MEDIA)
        .build()

    return ExoPlayer.Builder(context.applicationContext)
      .setSeekBackIncrementMs(15_000)
      .setSeekForwardIncrementMs(15_000)
      .build()
      .also {
        it.setAudioAttributes(audioAttributes, true)
        it.addListener(playerListener)
        player = it
      }
  }

  private fun createCuePlayer(context: Context): ExoPlayer {
    val audioAttributes =
      AudioAttributes.Builder()
        .setContentType(C.AUDIO_CONTENT_TYPE_SPEECH)
        .setUsage(C.USAGE_MEDIA)
        .build()

    return ExoPlayer.Builder(context.applicationContext)
      .build()
      .also {
        it.setAudioAttributes(audioAttributes, true)
        it.addListener(cuePlayerListener)
        cuePlayer = it
      }
  }

  private fun resolveCueAndRelease() {
    cuePromise?.resolve(null)
    cuePromise = null
    releaseCuePlayer()
  }

  private fun rejectCueAndRelease(message: String, error: Exception) {
    cuePromise?.reject("rsplayer_cue_error", message, error)
    cuePromise = null
    releaseCuePlayer()
  }

  private fun releaseCuePlayer() {
    cuePlayer?.removeListener(cuePlayerListener)
    cuePlayer?.release()
    cuePlayer = null
  }

  private fun buildDataSourceFactory(
    context: Context,
    options: ReadableMap
  ): DefaultDataSource.Factory {
    val httpFactory = DefaultHttpDataSource.Factory()
    if (options.hasKey("headers") && !options.isNull("headers")) {
      val headersMap = options.getMap("headers")
      val headers = mutableMapOf<String, String>()
      val iterator = headersMap?.keySetIterator()
      while (iterator?.hasNextKey() == true) {
        val key = iterator.nextKey()
        headers[key] = headersMap.getString(key) ?: ""
      }
      httpFactory.setDefaultRequestProperties(headers)
    }

    return DefaultDataSource.Factory(context.applicationContext, httpFactory)
  }

  private fun buildMetadata(options: ReadableMap): MediaMetadata {
    val builder = MediaMetadata.Builder()

    if (options.hasKey("title")) {
      builder.setTitle(options.getString("title"))
    }
    if (options.hasKey("artist")) {
      builder.setArtist(options.getString("artist"))
    }
    if (options.hasKey("artwork")) {
      options.getString("artwork")?.let { builder.setArtworkUri(Uri.parse(it)) }
    }

    return builder.build()
  }

  private fun currentState(activePlayer: ExoPlayer?): String {
    if (activePlayer == null) {
      return "idle"
    }

    return when (activePlayer.playbackState) {
      Player.STATE_BUFFERING -> "buffering"
      Player.STATE_READY -> if (activePlayer.isPlaying) "playing" else "paused"
      Player.STATE_ENDED -> "ended"
      else -> "idle"
    }
  }

  private fun startProgressUpdates() {
    if (progressRunnable != null) {
      return
    }

    progressRunnable =
      object : Runnable {
        override fun run() {
          emitProgress()
          mainHandler.postDelayed(this, PROGRESS_INTERVAL_MS)
        }
      }
    mainHandler.post(progressRunnable!!)
  }

  private fun stopProgressUpdates() {
    progressRunnable?.let { mainHandler.removeCallbacks(it) }
    progressRunnable = null
  }

  private fun emitLoad() {
    val activePlayer = player ?: return
    val payload =
      Arguments.createMap().apply {
        putString("type", "load")
        putDouble("duration", seconds(activePlayer.duration))
        putDouble("position", seconds(activePlayer.currentPosition))
        putDouble("buffered", seconds(activePlayer.bufferedPosition))
      }
    emit(payload)
  }

  private fun emitProgress() {
    val activePlayer = player ?: return
    val payload =
      Arguments.createMap().apply {
        putString("type", "progress")
        putDouble("position", seconds(activePlayer.currentPosition))
        putDouble("duration", seconds(activePlayer.duration))
        putDouble("buffered", seconds(activePlayer.bufferedPosition))
      }
    emit(payload)
  }

  private fun emitState(state: String) {
    emit(
      Arguments.createMap().apply {
        putString("type", "state")
        putString("state", state)
      }
    )
  }

  private fun emitEvent(type: String) {
    emit(
      Arguments.createMap().apply {
        putString("type", type)
      }
    )
  }

  private fun emitError(message: String) {
    emit(
      Arguments.createMap().apply {
        putString("type", "error")
        putString("message", message)
      }
    )
  }

  private fun emit(payload: WritableMap) {
    eventSink?.invoke(payload)
  }

  private fun ReadableMap.getBooleanOrDefault(key: String, defaultValue: Boolean): Boolean {
    return if (hasKey(key) && !isNull(key)) getBoolean(key) else defaultValue
  }

  private fun ReadableMap.getDoubleOrDefault(key: String, defaultValue: Double): Double {
    return if (hasKey(key) && !isNull(key)) getDouble(key) else defaultValue
  }

  private fun ReadableMap.getStringOrNull(key: String): String? {
    return if (hasKey(key) && !isNull(key)) getString(key) else null
  }

  private fun seconds(valueMs: Long): Double {
    if (valueMs == C.TIME_UNSET || valueMs < 0) {
      return 0.0
    }

    return valueMs / 1000.0
  }
}
