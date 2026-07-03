package com.rsplayer

import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.view.View.MeasureSpec
import android.widget.FrameLayout
import androidx.media3.common.C
import androidx.media3.common.AudioAttributes
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.uimanager.UIManagerHelper
import kotlin.math.max

@UnstableApi
class RSVideoView(context: Context) : FrameLayout(context), Player.Listener {
  private val trackSelector = DefaultTrackSelector(context)
  private val playerView =
    PlayerView(context).apply {
      layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
      resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
      setShutterBackgroundColor(Color.BLACK)
      useController = false
    }

  private var didEmitLoad = false
  private var muted = true
  private var paused = true
  private var pendingSeekMs: Long? = null
  private var player: ExoPlayer? = null
  private var resizeMode = "contain"
  private var playerResizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
  private var seekRequest = 0
  private var seekTime = 0.0
  private var sourceUri: String? = null
  private var videoHeight = 0
  private var videoWidth = 0

  private val layoutRunnable =
    Runnable {
      if (width > 0 && height > 0) {
        measure(
          MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
          MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY),
        )
        layout(left, top, right, bottom)
      }
    }

  private val videoAudioAttributes =
    AudioAttributes.Builder()
      .setContentType(C.AUDIO_CONTENT_TYPE_UNKNOWN)
      .setUsage(C.USAGE_MEDIA)
      .build()

  init {
    addView(playerView, 0, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    disableAudioTracks()
  }

  fun setSourceUri(nextSourceUri: String?) {
    val trimmedUri = nextSourceUri?.trim().orEmpty()
    if (sourceUri == trimmedUri) {
      return
    }

    sourceUri = trimmedUri
    didEmitLoad = false
    videoHeight = 0
    videoWidth = 0

    if (trimmedUri.isEmpty()) {
      stopPlayback()
      return
    }

    emit("topLoadStart", Arguments.createMap())

    val activePlayer = getOrCreatePlayer()
    activePlayer.setMediaItem(MediaItem.fromUri(Uri.parse(trimmedUri)))
    activePlayer.prepare()
    syncPlaybackState()
  }

  fun setPaused(nextPaused: Boolean) {
    paused = nextPaused
    syncPlaybackState()
  }

  fun setMuted(nextMuted: Boolean) {
    muted = nextMuted
    player?.volume = if (muted) 0f else 1f
    disableAudioTracks()
  }

  fun setResizeMode(nextResizeMode: String?) {
    resizeMode = nextResizeMode ?: "contain"
    playerResizeMode =
      when (resizeMode) {
        "cover" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
        "stretch" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
        else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
      }
    playerView.resizeMode = playerResizeMode
    forceLayoutRefresh()
  }

  fun seekToSeconds(seconds: Double) {
    val seekMs = (max(seconds, 0.0) * 1000).toLong()
    val activePlayer = player
    if (activePlayer == null || activePlayer.playbackState == Player.STATE_IDLE) {
      pendingSeekMs = seekMs
      return
    }

    activePlayer.seekTo(seekMs)
  }

  fun setSeekTime(nextSeekTime: Double) {
    seekTime = nextSeekTime
  }

  fun setSeekRequest(nextSeekRequest: Int) {
    if (seekRequest == nextSeekRequest) {
      return
    }

    seekRequest = nextSeekRequest
    seekToSeconds(seekTime)
  }

  fun release() {
    removeCallbacks(layoutRunnable)
    player?.removeListener(this)
    player?.release()
    player = null
    playerView.player = null
  }

  override fun requestLayout() {
    super.requestLayout()
    post(layoutRunnable)
  }

  override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
    super.onLayout(changed, left, top, right, bottom)

    if (changed) {
      playerView.resizeMode = playerResizeMode
    }
  }

  override fun onPlaybackStateChanged(playbackState: Int) {
    when (playbackState) {
      Player.STATE_BUFFERING -> emitBuffer(true)
      Player.STATE_READY -> {
        emitBuffer(false)
        emitLoadIfNeeded()
        applyPendingSeek()
        syncPlaybackState()
      }
      else -> Unit
    }
  }

  override fun onPlayerError(error: PlaybackException) {
    val errorMap =
      Arguments.createMap().apply {
        putMap(
          "error",
          Arguments.createMap().apply {
            putString("errorString", error.message ?: "Video playback failed.")
            putString("error", error.errorCodeName)
          },
        )
      }

    emit("topError", errorMap)
  }

  override fun onVideoSizeChanged(videoSize: VideoSize) {
    videoWidth = videoSize.width
    videoHeight = videoSize.height
    playerView.resizeMode = playerResizeMode
    forceLayoutRefresh()
  }

  private fun getOrCreatePlayer(): ExoPlayer {
    player?.let {
      disableAudioTracks()
      return it
    }

    val activePlayer =
      ExoPlayer.Builder(context)
        .setTrackSelector(trackSelector)
        .build()
        .apply {
          addListener(this@RSVideoView)
          setAudioAttributes(videoAudioAttributes, false)
          playWhenReady = !paused
          volume = if (muted) 0f else 1f
        }

    player = activePlayer
    playerView.player = activePlayer
    playerView.resizeMode = playerResizeMode
    disableAudioTracks()
    forceLayoutRefresh()

    return activePlayer
  }

  private fun disableAudioTracks() {
    val parametersBuilder = trackSelector.parameters.buildUpon()
    parametersBuilder.setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true)
    trackSelector.setParameters(parametersBuilder)
  }

  private fun syncPlaybackState() {
    player?.playWhenReady = !paused
  }

  private fun forceLayoutRefresh() {
    playerView.requestLayout()
    playerView.invalidate()
    requestLayout()
    invalidate()
  }

  private fun stopPlayback() {
    pendingSeekMs = null
    player?.stop()
    player?.clearMediaItems()
  }

  private fun emitLoadIfNeeded() {
    val activePlayer = player ?: return
    if (didEmitLoad) {
      return
    }

    didEmitLoad = true

    val durationSeconds =
      if (activePlayer.duration == C.TIME_UNSET) {
        0.0
      } else {
        activePlayer.duration / 1000.0
      }

    val event =
      Arguments.createMap().apply {
        putDouble("duration", durationSeconds)
        putMap(
          "naturalSize",
          Arguments.createMap().apply {
            putInt("width", videoWidth)
            putInt("height", videoHeight)
          },
        )
      }

    emit("topLoad", event)
  }

  private fun applyPendingSeek() {
    val seekMs = pendingSeekMs ?: return
    pendingSeekMs = null
    player?.seekTo(seekMs)
  }

  private fun emitBuffer(isBuffering: Boolean) {
    emit(
      "topBuffer",
      Arguments.createMap().apply {
        putBoolean("isBuffering", isBuffering)
      },
    )
  }

  private fun emit(eventName: String, eventData: com.facebook.react.bridge.WritableMap?) {
    if (id == View.NO_ID) {
      return
    }

    val reactContext = UIManagerHelper.getReactContext(this) as? ReactContext ?: return
    val dispatcher = UIManagerHelper.getEventDispatcherForReactTag(reactContext, id) ?: return
    dispatcher.dispatchEvent(
      RSVideoEvent(
        UIManagerHelper.getSurfaceId(this),
        id,
        eventName,
        eventData,
      ),
    )
  }
}
