package com.oliver.cadence

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Reads a "cadence://open?id=N" launch URI (sent by the widget trampoline) and
 * hands the task id to Flutter over a method channel, so tapping a widget row
 * jumps the app to that task.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "cadence/widget"
    private var channel: MethodChannel? = null
    private var pendingTaskId: Int? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel!!.setMethodCallHandler { call, result ->
            if (call.method == "consumeLaunchTask") {
                result.success(pendingTaskId)
                pendingTaskId = null
            } else {
                result.notImplemented()
            }
        }
        readTaskFromIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readTaskFromIntent(intent)
        pendingTaskId?.let { id ->
            channel?.invokeMethod("openTask", id)
            pendingTaskId = null
        }
    }

    private fun readTaskFromIntent(intent: Intent?) {
        val data = intent?.data ?: return
        if (data.host == "open") {
            data.getQueryParameter("id")?.toIntOrNull()?.let { pendingTaskId = it }
        }
    }
}
