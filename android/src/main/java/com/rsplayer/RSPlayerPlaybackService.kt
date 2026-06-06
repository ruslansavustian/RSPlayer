package com.rsplayer

import android.util.Log
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

@UnstableApi
class RSPlayerPlaybackService : MediaSessionService() {
  private var mediaSession: MediaSession? = null

  override fun onCreate() {
    super.onCreate()
    Log.d(TAG, "service created")

    val notificationProvider =
      DefaultMediaNotificationProvider.Builder(this)
        .setChannelId("rsplayer_audio_playback")
        .setChannelName(R.string.rsplayer_notification_channel_name)
        .setNotificationId(10080)
        .build()

    notificationProvider.setSmallIcon(R.drawable.rsplayer_ic_media_notification)
    setMediaNotificationProvider(notificationProvider)

    mediaSession =
      RSPlayerEngine.getOrCreateMediaSession(this).also { session ->
        if (!isSessionAdded(session)) {
          addSession(session)
        }
      }
  }

  override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
    Log.d(TAG, "controller connected: ${controllerInfo.packageName}")
    return mediaSession
  }

  override fun onUpdateNotification(
    session: MediaSession,
    startInForegroundRequired: Boolean
  ) {
    Log.d(TAG, "notification update, foreground=$startInForegroundRequired")
    super.onUpdateNotification(session, startInForegroundRequired)
  }

  override fun onDestroy() {
    Log.d(TAG, "service destroyed")
    mediaSession = null
    RSPlayerEngine.onPlaybackServiceDestroyed()
    super.onDestroy()
  }

  private companion object {
    private const val TAG = "RSPlayer"
  }
}
