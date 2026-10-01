package com.nischalpandey.kharcha

import android.app.Activity
import android.content.Intent
import androidx.core.content.FileProvider
import java.io.File

/**
 * Lends Android's installer the one update file the app downloaded.
 *
 * A class of its own rather than FileProvider itself: two providers with the
 * same class name cannot be declared in one app, and plugins declare theirs.
 * It only ever exposes the `updates` folder of the app's cache (see
 * res/xml/update_paths.xml).
 */
class UpdateFileProvider : FileProvider()

/** Installing an update that the app downloaded itself. */
object AppUpdates {
    private const val APK_TYPE = "application/vnd.android.package-archive"

    /**
     * Opens Android's installer on [path]. Returns `started`, or why not:
     *
     *  - `outside`: the file is not in the app's own updates folder;
     *  - `missing`: there is no such file;
     *  - `not_kharcha`: the file is not a Kharcha APK;
     *  - `no_installer`: Android refused to open its installer.
     *
     * Nothing is installed here. Android asks the user to confirm, and it
     * refuses any APK not signed with the key this app was signed with.
     */
    fun install(activity: Activity, path: String): String {
        val folder = File(activity.cacheDir, "updates").canonicalFile
        val file = File(path).canonicalFile
        if (file.parentFile != folder) return "outside"
        if (!file.isFile || file.length() == 0L) return "missing"

        @Suppress("DEPRECATION")
        val info = activity.packageManager.getPackageArchiveInfo(file.path, 0)
        if (info == null || info.packageName != activity.packageName) {
            return "not_kharcha"
        }

        return try {
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.updates",
                file,
            )
            activity.startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, APK_TYPE)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
            )
            "started"
        } catch (error: Exception) {
            "no_installer"
        }
    }
}
