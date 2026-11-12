package com.fabriciocotrim.subshaul

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Passes text shared from other apps (e.g. a YouTube link) to Flutter.
 * Only plain text is read; Flutter validates it before any request.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingText = sharedText(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "subshaul/share").also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "initialText") {
                    result.success(pendingText)
                    pendingText = null
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        sharedText(intent)?.let { channel?.invokeMethod("shared", it) }
    }

    private fun sharedText(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND || intent.type != "text/plain") return null
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return null
        // Shared text is untrusted input; cap its size.
        return if (text.length > 20_000) text.substring(0, 20_000) else text
    }
}
