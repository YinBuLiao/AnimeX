package com.animex.animex_mobile

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "animex/pip"
    private var pipEnabled: Boolean = false
    private var aspectNumerator: Int = 16
    private var aspectDenominator: Int = 9

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        pipEnabled = (call.argument<Boolean>("enabled") ?: false) &&
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                        call.argument<Int>("aspectNumerator")?.let {
                            if (it > 0) aspectNumerator = it
                        }
                        call.argument<Int>("aspectDenominator")?.let {
                            if (it > 0) aspectDenominator = it
                        }
                        result.success(pipEnabled)
                    }
                    "enterNow" -> {
                        result.success(enterPip())
                    }
                    "supported" -> {
                        result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipEnabled) {
            enterPip()
        }
    }

    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(aspectNumerator, aspectDenominator))
                .build()
            enterPictureInPictureMode(params)
        } catch (e: IllegalStateException) {
            false
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // Flutter rebuilds automatically on configChange — the player UI
        // can adapt by listening to MediaQuery if needed.
    }
}
