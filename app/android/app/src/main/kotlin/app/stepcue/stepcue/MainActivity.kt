package app.stepcue.stepcue

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "stepcue/monitor"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    requestNotificationPermission()
                    ContextCompat.startForegroundService(this, MonitorService.intent(this))
                    result.success(true)
                }
                "update" -> {
                    ContextCompat.startForegroundService(
                        this,
                        MonitorService.intent(this, call.argument<String>("text")),
                    )
                    result.success(true)
                }
                "stop" -> {
                    startService(Intent(this, MonitorService::class.java).setAction(MonitorService.ACTION_STOP))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }
}
