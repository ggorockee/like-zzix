package com.woohalabs.likezzix

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    /** 카메라 화면이 듣고 있을 때만 값이 있다. 없으면 볼륨 키는 원래대로 동작. */
    private var volumeSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "likezzix/volume_button")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    volumeSink = events
                }

                override fun onCancel(arguments: Any?) {
                    volumeSink = null
                }
            })
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val sink = volumeSink
        val isVolume = event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
            event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN
        if (sink == null || !isVolume) return super.dispatchKeyEvent(event)
        // 길게 눌러도 한 번만
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) sink.success(null)
        return true
    }
}
