package com.rsplayer

import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.events.Event

class RSVideoEvent(
  surfaceId: Int,
  viewId: Int,
  private val nativeEventName: String,
  private val eventData: WritableMap?,
) : Event<RSVideoEvent>(surfaceId, viewId) {
  override fun canCoalesce(): Boolean = false

  override fun getEventName(): String = nativeEventName

  public override fun getEventData(): WritableMap? = eventData
}
