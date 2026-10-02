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
 * The home-screen widgets and the shortcuts on the app's icon.
 *
 * There are three widgets: today's spending with an Add button, this month's
 * income, spending and savings, and a row of quick actions. None of them can
 * run Dart, so the app hands them ready-made text whenever its figures change
 * (see lib/services/home_widget_service.dart) and this side only stores and
 * shows it. The one thing worked out here is the day: the text for "today" is
 * only shown on the day it was written for, so a widget nobody has opened the
 * app behind does not show yesterday's spending as today's.
 *
 * A widget button and an icon shortcut (res/xml/shortcuts.xml) both open
 * MainActivity with one of the actions below, which it passes on to Dart.
 */
object KharchaWidget {
    const val ACTION_ADD_EXPENSE = "com.nischalpandey.kharcha.ADD_EXPENSE"
    const val ACTION_ADD_INCOME = "com.nischalpandey.kharcha.ADD_INCOME"
    const val ACTION_IMPORT_STATEMENT = "com.nischalpandey.kharcha.IMPORT_STATEMENT"
    const val ACTION_SCAN_SMS = "com.nischalpandey.kharcha.SCAN_SMS"

    /** The name Dart knows each action by. */
    private val actions = mapOf(
        ACTION_ADD_EXPENSE to "add_expense",
        ACTION_ADD_INCOME to "add_income",
        ACTION_IMPORT_STATEMENT to "import_statement",
        ACTION_SCAN_SMS to "scan_sms",
    )

    private const val PREFS = "kharcha_widget"

    /** The action an intent carries, by the name Dart knows it by. */
    fun actionOf(intent: Intent?): String? = actions[intent?.action]

    /** Stores what the app sent and redraws every widget on the home screen. */
    fun save(context: Context, values: Map<*, *>) {
        val editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear()
        for ((key, value) in values) {
            if (key is String && value is String) editor.putString(key, value)
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
        fun redraw(provider: Class<*>, views: RemoteViews) {
            val ids = manager.getAppWidgetIds(ComponentName(context, provider))
            if (ids.isNotEmpty()) manager.updateAppWidget(ids, views)
        }
        redraw(KharchaWidgetProvider::class.java, todayViews(context))
        redraw(KharchaMonthWidgetProvider::class.java, monthViews(context))
        redraw(KharchaActionsWidgetProvider::class.java, actionViews(context))
    }

    private fun open(context: Context, action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(action)
            .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (action == Intent.ACTION_MAIN) intent.addCategory(Intent.CATEGORY_LAUNCHER)
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** Today's spending and an Add button. */
    fun todayViews(context: Context): RemoteViews {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val views = RemoteViews(context.packageName, R.layout.kharcha_widget)
        val today = prefs.getString("today", null)

        if (today == null) {
            // Nobody is signed in, or the app has not been opened since the
            // widget was added: nothing private is shown.
            views.setTextViewText(R.id.widget_label, context.getString(R.string.app_widget_name))
            views.setTextViewText(R.id.widget_today, context.getString(R.string.app_widget_open))
            views.setTextViewText(R.id.widget_month, "")
        } else {
            val writtenFor = prefs.getString("day", null)
            val now = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
            views.setTextViewText(
                R.id.widget_label,
                prefs.getString("label", null) ?: context.getString(R.string.app_widget_today),
            )
            views.setTextViewText(
                R.id.widget_today,
                if (writtenFor == now) today else prefs.getString("zero", null) ?: today,
            )
            views.setTextViewText(R.id.widget_month, prefs.getString("month", null) ?: "")
        }
        views.setTextViewText(
            R.id.widget_add,
            prefs.getString("add", null) ?: context.getString(R.string.app_widget_add),
        )
        views.setOnClickPendingIntent(R.id.widget_root, open(context, Intent.ACTION_MAIN, 0))
        views.setOnClickPendingIntent(R.id.widget_add, open(context, ACTION_ADD_EXPENSE, 1))
        return views
    }

    /** This month's income, spending and what is left of the two. */
    fun monthViews(context: Context): RemoteViews {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val views = RemoteViews(context.packageName, R.layout.kharcha_widget_month)
        val signedIn = prefs.getString("spent", null) != null
        val dash = context.getString(R.string.app_widget_none)

        views.setTextViewText(
            R.id.widget_month_title,
            if (signedIn) {
                prefs.getString("monthTitle", null)
                    ?: context.getString(R.string.app_widget_this_month)
            } else {
                context.getString(R.string.app_widget_open)
            },
        )
        views.setTextViewText(
            R.id.widget_income_label,
            prefs.getString("incomeLabel", null) ?: context.getString(R.string.app_widget_income),
        )
        views.setTextViewText(
            R.id.widget_spent_label,
            prefs.getString("spentLabel", null) ?: context.getString(R.string.app_widget_spent),
        )
        views.setTextViewText(
            R.id.widget_saved_label,
            prefs.getString("savedLabel", null) ?: context.getString(R.string.app_widget_saved),
        )
        views.setTextViewText(R.id.widget_income, prefs.getString("income", null) ?: dash)
        views.setTextViewText(R.id.widget_spent, prefs.getString("spent", null) ?: dash)
        views.setTextViewText(R.id.widget_saved, prefs.getString("saved", null) ?: dash)
        views.setTextViewText(
            R.id.widget_month_expense,
            prefs.getString("expenseAction", null)
                ?: context.getString(R.string.shortcut_add_expense),
        )
        views.setTextViewText(
            R.id.widget_month_income,
            prefs.getString("incomeAction", null)
                ?: context.getString(R.string.shortcut_add_income),
        )
        views.setOnClickPendingIntent(R.id.widget_month_root, open(context, Intent.ACTION_MAIN, 0))
        views.setOnClickPendingIntent(R.id.widget_month_expense, open(context, ACTION_ADD_EXPENSE, 1))
        views.setOnClickPendingIntent(R.id.widget_month_income, open(context, ACTION_ADD_INCOME, 2))
        return views
    }

    /** Three buttons: add an expense, add income, import a statement. */
    fun actionViews(context: Context): RemoteViews {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val views = RemoteViews(context.packageName, R.layout.kharcha_widget_actions)
        views.setTextViewText(
            R.id.widget_action_expense,
            prefs.getString("expenseAction", null)
                ?: context.getString(R.string.shortcut_add_expense),
        )
        views.setTextViewText(
            R.id.widget_action_income,
            prefs.getString("incomeAction", null)
                ?: context.getString(R.string.shortcut_add_income),
        )
        views.setTextViewText(
            R.id.widget_action_import,
            prefs.getString("importAction", null)
                ?: context.getString(R.string.shortcut_import_short),
        )
        views.setOnClickPendingIntent(R.id.widget_action_expense, open(context, ACTION_ADD_EXPENSE, 1))
        views.setOnClickPendingIntent(R.id.widget_action_income, open(context, ACTION_ADD_INCOME, 2))
        views.setOnClickPendingIntent(
            R.id.widget_action_import,
            open(context, ACTION_IMPORT_STATEMENT, 3),
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
        appWidgetManager.updateAppWidget(appWidgetIds, KharchaWidget.todayViews(context))
    }
}

class KharchaMonthWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetManager.updateAppWidget(appWidgetIds, KharchaWidget.monthViews(context))
    }
}

class KharchaActionsWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetManager.updateAppWidget(appWidgetIds, KharchaWidget.actionViews(context))
    }
}
