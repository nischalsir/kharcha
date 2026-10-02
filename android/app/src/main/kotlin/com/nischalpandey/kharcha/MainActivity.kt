package com.nischalpandey.kharcha

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

// local_auth requires a FragmentActivity so the BiometricPrompt fragment can be
// attached; a plain FlutterActivity makes `authenticate()` throw.
class MainActivity : FlutterFragmentActivity() {

    private var incomingChannel: MethodChannel? = null
    private var widgetChannel: MethodChannel? = null

    /**
     * What a home-screen widget or an icon shortcut asked for, until Dart
     * has asked for it.
     */
    private var widgetAction: String? = null

    /** The intent this activity was opened with, until Dart has asked for it. */
    private var launchIntent: Intent? = null
    private val copier = Executors.newSingleThreadExecutor()

    /** The Dart call waiting for the contact picker to close. */
    private var contactResult: MethodChannel.Result? = null

    // Registered while the activity is being created, as Android requires.
    private val contactPicker = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { outcome ->
        val pending = contactResult
        contactResult = null
        val uri = outcome.data?.data
        if (pending != null) {
            if (outcome.resultCode != RESULT_OK || uri == null) {
                // The user backed out: nothing was chosen.
                pending.success(null)
            } else {
                val contact = ContactPicks.read(this, uri)
                if (contact == null) {
                    pending.error("unreadable", "The contact could not be read.", null)
                } else {
                    pending.success(contact)
                }
            }
        }
    }

    /** The Dart call waiting for the SMS permission dialog to close. */
    private var smsPermissionResult: MethodChannel.Result? = null

    private val smsPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        val pending = smsPermissionResult
        smsPermissionResult = null
        pending?.success(granted)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Only a fresh start carries a share to act on. After a rotation or a
        // restore the same intent comes back, and its file was already taken.
        // Reopening the app from Recents replays the old intent too.
        val replayed =
            (intent?.flags ?: 0) and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0
        if (savedInstanceState == null && !replayed) {
            launchIntent = intent
            widgetAction = KharchaWidget.actionOf(intent)
        }
        super.onCreate(savedInstanceState)
    }

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

        // What this build was configured with, for features that can only be
        // offered when the configuration is there.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_CONFIG_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // The Google web client id, which the Google Services plugin
                // generates as a string resource from google-services.json
                // only when the Firebase project has such a client. Looked
                // up by name: referring to R.string directly would not
                // compile when it is absent.
                "googleWebClientId" -> {
                    @Suppress("DiscouragedApi")
                    val id = resources.getIdentifier(
                        "default_web_client_id",
                        "string",
                        packageName,
                    )
                    result.success(if (id == 0) null else getString(id))
                }

                else -> result.notImplemented()
            }
        }

        // An update the app downloaded, handed to Android's installer.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_UPDATE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "install" -> {
                    val path = call.argument<String>("path")
                    result.success(
                        if (path == null) "missing" else AppUpdates.install(this, path),
                    )
                }

                else -> result.notImplemented()
            }
        }

        // One phone number chosen from the phone's contacts.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CONTACTS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickPhone" -> {
                    if (contactResult != null) {
                        result.error("busy", "The contact picker is already open.", null)
                    } else {
                        contactResult = result
                        try {
                            contactPicker.launch(ContactPicks.intent())
                        } catch (error: ActivityNotFoundException) {
                            contactResult = null
                            result.error("no_app", "No contacts app was found.", null)
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }

        // The home-screen widget: the app sends it its figures, and it sends
        // back the tap on its Add button.
        widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HOME_WIDGET_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        val values = call.arguments as? Map<*, *>
                        if (values == null) {
                            result.error("bad_args", "Expected a map.", null)
                        } else {
                            KharchaWidget.save(applicationContext, values)
                            result.success(null)
                        }
                    }

                    "clear" -> {
                        KharchaWidget.clear(applicationContext)
                        result.success(null)
                    }

                    "takeInitialAction" -> {
                        val pending = widgetAction
                        widgetAction = null
                        result.success(pending)
                    }

                    else -> result.notImplemented()
                }
            }
        }

        // Bank and wallet payment alerts among the phone's text messages.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SMS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(SmsReader.hasPermission(this))

                "requestPermission" -> {
                    if (SmsReader.hasPermission(this)) {
                        result.success(true)
                    } else if (smsPermissionResult != null) {
                        result.error("busy", "Already asking.", null)
                    } else {
                        smsPermissionResult = result
                        smsPermission.launch(Manifest.permission.READ_SMS)
                    }
                }

                // Where "Allow restricted settings" and the SMS permission
                // are, for a phone that refused to ask.
                "openAppSettings" -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null),
                        ),
                    )
                    result.success(true)
                }

                "read" -> {
                    val since = (call.argument<Number>("since") ?: 0).toLong()
                    val limit = (call.argument<Number>("limit") ?: 500).toInt()
                    copier.execute {
                        val messages = SmsReader.read(applicationContext, since, limit)
                        runOnUiThread { result.success(messages) }
                    }
                }

                else -> result.notImplemented()
            }
        }

        // A statement shared into the app from a bank app or a file manager.
        incomingChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            INCOMING_FILE_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeInitial" -> {
                        val pending = launchIntent
                        launchIntent = null
                        val uri = IncomingFiles.uriOf(pending)
                        if (pending == null || uri == null) {
                            result.success(null)
                        } else {
                            copier.execute {
                                val file = IncomingFiles.copy(
                                    applicationContext,
                                    uri,
                                    pending.type,
                                )
                                runOnUiThread { result.success(file) }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
        }
    }

    // The app is already open (singleTop) and something else was shared in.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val action = KharchaWidget.actionOf(intent)
        if (action != null) {
            val widget = widgetChannel
            // The engine is not up yet: keep it for `takeInitialAction`.
            if (widget == null) widgetAction = action else widget.invokeMethod("action", action)
            return
        }
        val uri = IncomingFiles.uriOf(intent) ?: return
        val channel = incomingChannel
        if (channel == null) {
            // The engine is not up yet: keep it for `takeInitial`.
            launchIntent = intent
            return
        }
        copier.execute {
            val file = IncomingFiles.copy(applicationContext, uri, intent.type)
            runOnUiThread { channel.invokeMethod("incomingFile", file) }
        }
    }

    override fun onDestroy() {
        copier.shutdown()
        super.onDestroy()
    }

    private companion object {
        const val NOTIFICATION_SETTINGS_CHANNEL =
            "com.nischalpandey.kharcha/notification_settings"
        const val INCOMING_FILE_CHANNEL =
            "com.nischalpandey.kharcha/incoming_file"
        const val APP_CONFIG_CHANNEL =
            "com.nischalpandey.kharcha/app_config"
        const val APP_UPDATE_CHANNEL =
            "com.nischalpandey.kharcha/app_update"
        const val CONTACTS_CHANNEL =
            "com.nischalpandey.kharcha/contacts"
        const val HOME_WIDGET_CHANNEL =
            "com.nischalpandey.kharcha/home_widget"
        const val SMS_CHANNEL =
            "com.nischalpandey.kharcha/sms"
    }
}
