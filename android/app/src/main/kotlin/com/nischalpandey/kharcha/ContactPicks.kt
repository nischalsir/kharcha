package com.nischalpandey.kharcha

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.ContactsContract.CommonDataKinds.Phone

/**
 * Choosing one phone number from the phone's contacts.
 *
 * Android's own picker is opened on the list of phone numbers. It hands back
 * a link to the one row the user tapped, with leave to read that row and
 * nothing else, so the app needs no contacts permission and never sees the
 * rest of the address book.
 */
object ContactPicks {
    /** The intent that opens the picker. */
    fun intent(): Intent = Intent(Intent.ACTION_PICK, Phone.CONTENT_URI)

    /**
     * The number and name behind [uri], the row the picker returned, or null
     * when it cannot be read.
     */
    fun read(context: Context, uri: Uri): Map<String, String?>? {
        return try {
            context.contentResolver.query(
                uri,
                arrayOf(Phone.NUMBER, Phone.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return null
                val number = cursor.getString(0) ?: return null
                mapOf("number" to number, "name" to cursor.getString(1))
            }
        } catch (error: Exception) {
            null
        }
    }
}
