package com.nischalpandey.kharcha

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Telephony
import androidx.core.content.ContextCompat

/**
 * Reads the phone's received text messages, for finding bank and wallet
 * payment alerts.
 *
 * Only ever called when the user asks for a scan (or has switched on the
 * check at app start), and only after they granted READ_SMS. The messages are
 * handed to Dart, which keeps the payment alerts and drops the rest; nothing
 * is stored or sent anywhere from here.
 */
object SmsReader {
    /** A scan never needs more than this; it only stops a runaway query. */
    private const val MAX_MESSAGES = 2000

    fun hasPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_SMS) ==
            PackageManager.PERMISSION_GRANTED

    /**
     * Messages received after [since] (milliseconds since the epoch), newest
     * first. Empty when the permission is missing or the inbox cannot be read.
     */
    fun read(context: Context, since: Long, limit: Int): List<Map<String, Any?>> {
        if (!hasPermission(context)) return emptyList()
        val wanted = limit.coerceIn(1, MAX_MESSAGES)
        val messages = ArrayList<Map<String, Any?>>()
        try {
            context.contentResolver.query(
                Telephony.Sms.Inbox.CONTENT_URI,
                arrayOf(
                    Telephony.Sms._ID,
                    Telephony.Sms.ADDRESS,
                    Telephony.Sms.BODY,
                    Telephony.Sms.DATE,
                ),
                "${Telephony.Sms.DATE} > ?",
                arrayOf(since.toString()),
                "${Telephony.Sms.DATE} DESC",
            )?.use { cursor ->
                val id = cursor.getColumnIndexOrThrow(Telephony.Sms._ID)
                val address = cursor.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
                val body = cursor.getColumnIndexOrThrow(Telephony.Sms.BODY)
                val date = cursor.getColumnIndexOrThrow(Telephony.Sms.DATE)
                while (cursor.moveToNext() && messages.size < wanted) {
                    messages.add(
                        mapOf(
                            "id" to cursor.getLong(id),
                            "sender" to (cursor.getString(address) ?: ""),
                            "body" to (cursor.getString(body) ?: ""),
                            "date" to cursor.getLong(date),
                        ),
                    )
                }
            }
        } catch (_: Exception) {
            // Another app is the SMS app and refuses, or the provider is
            // missing (a tablet): there is simply nothing to read.
            return emptyList()
        }
        return messages
    }
}
