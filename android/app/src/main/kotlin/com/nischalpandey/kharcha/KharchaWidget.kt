package com.nischalpandey.kharcha

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The home-screen widget: what was spent today and this month, and a button
 * that opens the app straight on "Add expense".
 *
 * The widget cannot run Dart, so the app hands it ready-made text whenever
 * its figures change (see lib/services/home_widget_service.dart) and this
 * side only stores and shows it. The one thing worked out here is the day:
 * the text for "today" is only shown on the day it was written for, so a
 * widget nobody has opened the app behind does not show yesterday's spending
 * as today's.
 */
object KharchaWidget {
    /** Opens the app on the Add expense page. */
    const val ACTION_ADD_EXPENSE = "com.nischalpandey.kharcha.ADD_EXPENSE"

    private const val PREFS = "kharcha_widget"
    private const val KEY_DAY = "day"
    private const val KEY_TODAY = "today"
    private const val KEY_ZERO = "zero"
    private const val KEY_MONTH = "month"
    private const val KEY_LABEL = "label"
    private const val KEY_ADD = "add"

    /** Stores what the app sent and redraws every widget on the home screen. */
    fun save(context: Context, values: Map<*, *>) {
        val editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        for (key in listOf(KEY_DAY, KEY_TODAY, KEY_ZERO, KEY_MONTH, KEY_LABEL, KEY_ADD)) {
            val value = values[key] as? String
            if (value == null) editor.remove(key) else editor.putString(key, value)
        }
        editor.apply()
        refresh(context)
    }

    /** Forgets the figures, when the account they belong to signs out. */
    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
        refresh(context)
    }

    fun refresh(context: Context) {
        val manager = AppWidgetManager.getInstance(context) ?: return
        val ids = manager.getAppWidgetIds(
            ComponentName(context, KharchaWidgetProvider::class.java),
        )
        if (ids.isNotEmpty()) manager.updateAppWidget(ids, views(context))
    }

    fun views(context: Context): RemoteViews {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val views = RemoteViews(context.packageName, R.layout.kharcha_widget)
        val today = prefs.getString(KEY_TODAY, null)

        if (today == null) {
            // Nobody is signed in, or the app has not been opened since the
            // widget was added: nothing private is shown.
            views.setTextViewText(R.id.widget_label, context.getString(R.string.app_widget_name))
            views.setTextViewText(R.id.widget_today, context.getString(R.string.app_widget_open))
            views.setTextViewText(R.id.widget_month, "")
        } else {
            val writtenFor = prefs.getString(KEY_DAY, null)
            val now = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
            views.setTextViewText(
                R.id.widget_label,
                prefs.getString(KEY_LABEL, null) ?: context.getString(R.string.app_widget_today),
            )
            views.setTextViewText(
                R.id.widget_today,
                if (writtenFor == now) today else prefs.getString(KEY_ZERO, null) ?: today,
            )
            views.setTextViewText(R.id.widget_month, prefs.getString(KEY_MONTH, null) ?: "")
        }
        views.setTextViewText(
            R.id.widget_add,
            prefs.getString(KEY_ADD, null) ?: context.getString(R.string.app_widget_add),
        )

        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val open = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        views.setOnClickPendingIntent(
            R.id.widget_root,
            PendingIntent.getActivity(context, 0, open, flags),
        )
        val add = Intent(context, MainActivity::class.java)
            .setAction(ACTION_ADD_EXPENSE)
            .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        views.setOnClickPendingIntent(
            R.id.widget_add,
            PendingIntent.getActivity(context, 1, add, flags),
        )
        return views
    }
}

class KharchaWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetManager.updateAppWidget(appWidgetIds, KharchaWidget.views(context))
    }
}
