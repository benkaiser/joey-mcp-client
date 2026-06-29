package com.kaiserapps.joey

import android.content.Intent
import android.provider.AlarmClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.kaiserapps.joey/local_alarm"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "createAlarm" -> {
                    val hour = call.argument<Int>("hour")
                    val minute = call.argument<Int>("minute")
                    val label = call.argument<String>("label")
                    if (hour == null || minute == null) {
                        result.error("invalid_args", "hour and minute are required", null)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                        putExtra(AlarmClock.EXTRA_HOUR, hour)
                        putExtra(AlarmClock.EXTRA_MINUTES, minute)
                        putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                        if (!label.isNullOrBlank()) {
                            putExtra(AlarmClock.EXTRA_MESSAGE, label)
                        }
                    }
                    if (intent.resolveActivity(packageManager) == null) {
                        result.error("no_alarm_app", "No alarm app is available", null)
                        return@setMethodCallHandler
                    }
                    startActivity(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
