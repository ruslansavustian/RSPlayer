package com.rsplayer

import android.os.Handler
import android.os.Looper
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.modules.core.DeviceEventManagerModule

class RSPlayerModule(
  private val reactContext: ReactApplicationContext
) : ReactContextBaseJavaModule(reactContext) {

  private val mainHandler = Handler(Looper.getMainLooper())

  init {
    RSPlayerEngine.attach(reactContext) { emit(it) }
  }

  override fun getName(): String = "RSPlayer"

  override fun invalidate() {
    RSPlayerEngine.clearEventSink()
    super.invalidate()
  }

  @ReactMethod
  fun addListener(eventName: String) {
    // Required by React Native's NativeEventEmitter.
  }

  @ReactMethod
  fun removeListeners(count: Int) {
    // Required by React Native's NativeEventEmitter.
  }

  @ReactMethod
  fun load(options: ReadableMap, promise: Promise) {
    runOnMain(promise) {
      RSPlayerEngine.load(reactContext, options)
    }
  }

  @ReactMethod
  fun play(promise: Promise) {
    runOnMain(promise) {
      RSPlayerEngine.play(reactContext)
    }
  }

  @ReactMethod
  fun pause(promise: Promise) {
    runOnMain(promise) {
      RSPlayerEngine.pause()
    }
  }

  @ReactMethod
  fun stop(promise: Promise) {
    runOnMain(promise) {
      RSPlayerEngine.stop()
    }
  }

  @ReactMethod
  fun reset(promise: Promise) {
    runOnMain(promise) {
      RSPlayerEngine.reset(reactContext)
    }
  }

  @ReactMethod
  fun seekTo(seconds: Double, promise: Promise) {
    runOnMain(promise) {
      RSPlayerEngine.seekTo(seconds)
    }
  }

  @ReactMethod
  fun setVolume(volume: Double, promise: Promise) {
    runOnMain(promise) {
      RSPlayerEngine.setVolume(volume)
    }
  }

  @ReactMethod
  fun setLoop(loop: Boolean, promise: Promise) {
    runOnMain(promise) {
      RSPlayerEngine.setLoop(loop)
    }
  }

  @ReactMethod
  fun getState(promise: Promise) {
    mainHandler.post {
      promise.resolve(RSPlayerEngine.getState())
    }
  }

  private fun emit(payload: com.facebook.react.bridge.WritableMap) {
    reactContext
      .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(EVENT_NAME, payload)
  }

  private fun runOnMain(promise: Promise, block: () -> Unit) {
    mainHandler.post {
      try {
        block()
        promise.resolve(null)
      } catch (error: Exception) {
        promise.reject("rsplayer_error", error.message, error)
      }
    }
  }

  companion object {
    private const val EVENT_NAME = "RSPlayerEvent"
  }
}
