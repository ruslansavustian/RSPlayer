package com.rsplayer

import androidx.media3.common.util.UnstableApi
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewGroupManager
import com.facebook.react.uimanager.annotations.ReactProp

@UnstableApi
class RSVideoViewManager : ViewGroupManager<RSVideoView>() {
  override fun getName(): String = REACT_CLASS

  override fun createViewInstance(reactContext: ThemedReactContext): RSVideoView =
    RSVideoView(reactContext)

  override fun onDropViewInstance(view: RSVideoView) {
    view.release()
    super.onDropViewInstance(view)
  }

  override fun getExportedCustomDirectEventTypeConstants(): Map<String, Any> =
    mapOf(
      "topLoadStart" to mapOf("registrationName" to "onLoadStart"),
      "topLoad" to mapOf("registrationName" to "onLoad"),
      "topBuffer" to mapOf("registrationName" to "onBuffer"),
      "topError" to mapOf("registrationName" to "onError"),
    )

  @ReactProp(name = "sourceUri")
  fun setSourceUri(view: RSVideoView, sourceUri: String?) {
    view.setSourceUri(sourceUri)
  }

  @ReactProp(name = "paused", defaultBoolean = false)
  fun setPaused(view: RSVideoView, paused: Boolean) {
    view.setPaused(paused)
  }

  @ReactProp(name = "muted", defaultBoolean = true)
  fun setMuted(view: RSVideoView, muted: Boolean) {
    view.setMuted(muted)
  }

  @ReactProp(name = "resizeMode")
  fun setResizeMode(view: RSVideoView, resizeMode: String?) {
    view.setResizeMode(resizeMode)
  }

  @ReactProp(name = "seekTime", defaultDouble = 0.0)
  fun setSeekTime(view: RSVideoView, seekTime: Double) {
    view.setSeekTime(seekTime)
  }

  @ReactProp(name = "seekRequest", defaultInt = 0)
  fun setSeekRequest(view: RSVideoView, seekRequest: Int) {
    view.setSeekRequest(seekRequest)
  }

  private companion object {
    const val REACT_CLASS = "RSVideoView"
  }
}
