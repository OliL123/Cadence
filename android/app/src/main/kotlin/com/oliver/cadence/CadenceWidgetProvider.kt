package com.oliver.cadence

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Home-screen widget mirroring Cadence. Two pages — 全部 (all tasks) and 麻雀
 * (the Focus wall) — switched by the header tabs. Each row can be completed (✓,
 * stays visible struck-through) or added to / removed from focus (★). Taps run
 * a background Dart callback (lib/home_widget_bridge.dart); the title opens the
 * app.
 */
class CadenceWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_SET_PAGE = "com.oliver.cadence.SET_PAGE"
        const val EXTRA_PAGE = "page"
        const val PREF_PAGE = "cadence_page"
        const val PAGE_ALL = "all"
        const val PAGE_FOCUS = "focus"

        fun currentPage(context: Context): String =
            HomeWidgetPlugin.getData(context).getString(PREF_PAGE, PAGE_FOCUS) ?: PAGE_FOCUS
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val page = currentPage(context)
        for (widgetId in appWidgetIds) {
            render(context, appWidgetManager, widgetId, page)
        }
        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.wall_list)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_SET_PAGE) {
            val page = intent.getStringExtra(EXTRA_PAGE) ?: PAGE_FOCUS
            HomeWidgetPlugin.getData(context).edit().putString(PREF_PAGE, page).apply()
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(
                ComponentName(context, CadenceWidgetProvider::class.java)
            )
            for (id in ids) render(context, mgr, id, page)
            mgr.notifyAppWidgetViewDataChanged(ids, R.id.wall_list)
        }
    }

    private fun render(
        context: Context,
        mgr: AppWidgetManager,
        widgetId: Int,
        page: String
    ) {
        // Pick the pre-styled layout for the active tab (avoids restyling the
        // tabs at runtime, which RemoteViews can't reliably apply).
        val layoutRes = if (page == PAGE_ALL) R.layout.cadence_widget_all
        else R.layout.cadence_widget
        val views = RemoteViews(context.packageName, layoutRes)

        // Header shows a "due today" count when there is one.
        val due = HomeWidgetPlugin.getData(context).getString("cadence_due", "0") ?: "0"
        val title = if (due != "0") "節奏 · $due due today" else "節奏 Cadence"
        views.setTextViewText(R.id.header_title, title)

        // Bind the list; a unique data URI makes the adapter refresh per widget.
        val adapterIntent = Intent(context, WallWidgetService::class.java).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
        }
        views.setRemoteAdapter(R.id.wall_list, adapterIntent)
        views.setEmptyView(R.id.wall_list, R.id.empty_view)

        // Tab taps -> switch page (broadcast back to this provider).
        views.setOnClickPendingIntent(R.id.tab_all, pageIntent(context, widgetId, PAGE_ALL))
        views.setOnClickPendingIntent(R.id.tab_focus, pageIntent(context, widgetId, PAGE_FOCUS))

        // Title tap -> open the app.
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        if (launch != null) {
            val pi = PendingIntent.getActivity(
                context, 0, launch,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.header_title, pi)
        }

        // Template for per-row taps -> home_widget's background receiver. Base
        // intent carries NO data so each row's fillInIntent supplies its own URI.
        val base = Intent(
            context,
            es.antonborri.home_widget.HomeWidgetBackgroundReceiver::class.java
        ).apply {
            action = "es.antonborri.home_widget.action.BACKGROUND"
        }
        val template = PendingIntent.getBroadcast(
            context, widgetId, base,
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        views.setPendingIntentTemplate(R.id.wall_list, template)

        mgr.updateAppWidget(widgetId, views)
    }

    private fun pageIntent(context: Context, widgetId: Int, page: String): PendingIntent {
        val intent = Intent(context, CadenceWidgetProvider::class.java).apply {
            action = ACTION_SET_PAGE
            putExtra(EXTRA_PAGE, page)
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
        }
        val rc = widgetId * 10 + if (page == PAGE_ALL) 1 else 2
        return PendingIntent.getBroadcast(
            context, rc, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
