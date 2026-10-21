package app.milos.member

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.DateFormat
import java.time.Instant
import java.util.Date
import java.util.concurrent.Executors

/**
 * ADR-173: the three home-screen widgets. Each fetches the snapshot off the
 * main thread (`goAsync`), shows the last one while offline, and asks to
 * open the app when there is no valid token. Android refreshes them every
 * 30 minutes (`updatePeriodMillis`); the app refreshes them when it opens.
 */
abstract class MilosWidgetProvider : AppWidgetProvider() {
    abstract fun render(context: Context, snapshot: JSONObject?): RemoteViews

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        refresh(context, manager, ids) { MilosWidgetData.fetchSnapshot(it) }
    }

    protected fun refresh(context: Context, manager: AppWidgetManager, ids: IntArray, load: (Context) -> JSONObject?) {
        val pending = goAsync()
        executor.execute {
            try {
                val snapshot = load(context) ?: MilosWidgetData.cachedSnapshot(context)
                val views = render(context, if (MilosWidgetData.session(context) == null) null else snapshot)
                ids.forEach { manager.updateAppWidget(it, views) }
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        private val executor = Executors.newSingleThreadExecutor()

        /** Redraws every Milos widget (after sign-in, sign-out or a language change). */
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            listOf(WaterWidgetProvider::class.java, TodayWidgetProvider::class.java, CheckInWidgetProvider::class.java).forEach { type ->
                val ids = manager.getAppWidgetIds(ComponentName(context, type))
                if (ids.isNotEmpty()) {
                    context.sendBroadcast(
                        Intent(context, type).setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE).putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids),
                    )
                }
            }
        }

        fun time(context: Context, iso: String?): String {
            if (iso.isNullOrEmpty() || iso == "null") return ""
            return runCatching { DateFormat.getTimeInstance(DateFormat.SHORT).format(Date.from(Instant.parse(iso))) }.getOrDefault("")
        }

        fun line(context: Context, item: JSONObject): String {
            val kind = MilosWidgetData.label(context, item.optString("kind"), item.optString("kind"))
            val title = item.optString("title").takeUnless { it.isEmpty() || it == "null" } ?: kind
            val at = time(context, item.optString("at"))
            return listOf(at, title).filter { it.isNotEmpty() }.joinToString(" · ")
        }
    }
}

/** «+1 νερό»: today's water against the goal and a button that adds a glass. */
class WaterWidgetProvider : MilosWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_ADD_WATER) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, WaterWidgetProvider::class.java))
            refresh(context, manager, ids) { MilosWidgetData.addWater(it) }
        } else {
            super.onReceive(context, intent)
        }
    }

    override fun render(context: Context, snapshot: JSONObject?): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_water)
        views.setTextViewText(R.id.widget_title, MilosWidgetData.label(context, "water", "Water"))
        views.setOnClickPendingIntent(R.id.widget_root, MilosWidgetData.openPathIntent(context, "water", 1))
        val water = snapshot?.optJSONObject("water")
        if (water == null) {
            views.setTextViewText(R.id.widget_value, MilosWidgetData.label(context, "openApp", "Open Milos"))
            views.setViewVisibility(R.id.widget_action, View.GONE)
            return views
        }
        views.setTextViewText(R.id.widget_value, "${water.optInt("ml")} / ${water.optInt("goal_ml")} ml")
        views.setViewVisibility(R.id.widget_action, View.VISIBLE)
        views.setTextViewText(R.id.widget_action, MilosWidgetData.label(context, "addGlass", "+1"))
        // Without the health-data consent the button opens the app instead.
        val action = if (water.optBoolean("can_add")) {
            PendingIntent.getBroadcast(
                context,
                2,
                Intent(context, WaterWidgetProvider::class.java).setAction(ACTION_ADD_WATER),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        } else {
            MilosWidgetData.openPathIntent(context, "water", 3)
        }
        views.setOnClickPendingIntent(R.id.widget_action, action)
        return views
    }

    companion object {
        const val ACTION_ADD_WATER = "app.milos.member.widget.ADD_WATER"
    }
}

/** Σήμερα: the first items of the day (WOD, programme, classes). */
class TodayWidgetProvider : MilosWidgetProvider() {
    override fun render(context: Context, snapshot: JSONObject?): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today)
        views.setTextViewText(R.id.widget_title, MilosWidgetData.label(context, "today", "Today"))
        views.setOnClickPendingIntent(R.id.widget_root, MilosWidgetData.openPathIntent(context, "today", 4))
        val items = snapshot?.optJSONArray("today")
        val text = when {
            snapshot == null -> MilosWidgetData.label(context, "openApp", "Open Milos")
            items == null || items.length() == 0 -> MilosWidgetData.label(context, "nothingToday", "Nothing for today")
            else -> (0 until items.length()).joinToString("\n") { line(context, items.getJSONObject(it)) }
        }
        views.setTextViewText(R.id.widget_value, text)
        return views
    }
}

/** Check-in: the next booked class; a tap opens the personal QR in the app. */
class CheckInWidgetProvider : MilosWidgetProvider() {
    override fun render(context: Context, snapshot: JSONObject?): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_checkin)
        views.setTextViewText(R.id.widget_title, MilosWidgetData.label(context, "checkIn", "Check-in"))
        views.setOnClickPendingIntent(R.id.widget_root, MilosWidgetData.openPathIntent(context, "checkIn", 5))
        val next = snapshot?.optJSONObject("next_class")
        val text = when {
            snapshot == null -> MilosWidgetData.label(context, "openApp", "Open Milos")
            next == null -> MilosWidgetData.label(context, "noClass", "No booking today")
            else -> listOf(line(context, next), next.optString("box_name").takeUnless { it.isEmpty() || it == "null" } ?: "")
                .filter { it.isNotEmpty() }
                .joinToString("\n")
        }
        views.setTextViewText(R.id.widget_value, text)
        return views
    }
}
