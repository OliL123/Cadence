package com.oliver.cadence

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Invisible trampoline for widget row taps. It's an Activity (not a receiver)
 * so that a row tap can reliably launch the app on modern Android, where a
 * background broadcast receiver is not allowed to start an activity.
 *
 *  cadence://open   -> open the app (MainActivity)
 *  cadence://toggle -> forward to home_widget's background receiver (mark done)
 *  cadence://star   -> forward to home_widget's background receiver (focus)
 *
 * The toggle/star cases finish immediately with no UI, so they stay "silent"
 * exactly like before; only "open" brings the app to the foreground.
 */
class WidgetActionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uri = intent?.data
        val host = uri?.host

        if (host == "open") {
            // Launch the app carrying the task URI so it can jump to that task.
            val launch = Intent(this, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = uri
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            startActivity(launch)
        } else if (uri != null) {
            // Forward to home_widget's background receiver, which runs the Dart
            // interactivity callback (toggle/star) without opening the app.
            val forward = Intent(
                this,
                es.antonborri.home_widget.HomeWidgetBackgroundReceiver::class.java
            ).apply {
                action = "es.antonborri.home_widget.action.BACKGROUND"
                data = uri
            }
            sendBroadcast(forward)
        }
        finish()
    }
}
