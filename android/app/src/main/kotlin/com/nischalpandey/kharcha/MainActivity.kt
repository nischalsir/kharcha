package com.nischalpandey.kharcha

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// local_auth requires a FragmentActivity so the BiometricPrompt fragment can be
// attached; a plain FlutterActivity makes `authenticate()` throw.
class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // The FCM plugin exposes no way to reach the app's notification
        // settings, and once Android 13 permission is permanently denied the
        // plugin will not show another dialog. This is the recovery path.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_SETTINGS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openAppNotificationSettings" -> {
                    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    if (intent.resolveActivity(packageManager) != null) {
                        startActivity(intent)
                        result.success(true)
                    } else {
                        // Fall back to the app's own settings page, which always
                        // exists, so the user still lands somewhere useful.
                        startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.fromParts("package", packageName, null),
                            ),
                        )
                        result.success(true)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private companion object {
        const val NOTIFICATION_SETTINGS_CHANNEL =
            "com.nischalpandey.kharcha/notification_settings"
    }
}
