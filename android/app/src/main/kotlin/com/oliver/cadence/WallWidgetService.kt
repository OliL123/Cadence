package com.oliver.cadence

import android.content.Context
import android.content.Intent
import android.graphics.Paint
import android.net.Uri
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

/** Serves rows for whichever page (全部 / 麻雀) the widget is currently showing. */
class WallWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        WallViewsFactory(applicationContext)
}

class WallViewsFactory(private val context: Context) :
    RemoteViewsService.RemoteViewsFactory {

    private var items: JSONArray = JSONArray()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        val prefs = HomeWidgetPlugin.getData(context)
        val page = prefs.getString(CadenceWidgetProvider.PREF_PAGE,
            CadenceWidgetProvider.PAGE_FOCUS) ?: CadenceWidgetProvider.PAGE_FOCUS
        val key = if (page == CadenceWidgetProvider.PAGE_ALL) "cadence_all" else "cadence_focus"
        val json = prefs.getString(key, "[]") ?: "[]"
        items = try {
            JSONArray(json)
        } catch (e: Exception) {
            JSONArray()
        }
    }

    override fun onDestroy() {}

    override fun getCount(): Int = items.length()

    override fun getViewAt(position: Int): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.cadence_widget_item)
        val o = items.optJSONObject(position) ?: return row

        val id = o.optInt("id")
        val title = o.optString("title")
        val color = o.optLong("color").toInt() // ARGB packed in a Long, wrap to Int
        val done = o.optBoolean("done")
        val star = o.optBoolean("star")

        row.setTextViewText(R.id.item_title, title)
        row.setInt(R.id.item_stripe, "setColorFilter", color)
        row.setImageViewResource(
            R.id.item_check,
            if (done) R.drawable.ic_check_done else R.drawable.ic_check_todo
        )
        row.setImageViewResource(
            R.id.item_star,
            if (star) R.drawable.ic_star_filled else R.drawable.ic_star_outline
        )
        // Strike through + dim a completed row.
        row.setInt(R.id.item_title, "setPaintFlags",
            Paint.ANTI_ALIAS_FLAG or (if (done) Paint.STRIKE_THRU_TEXT_FLAG else 0))
        row.setTextColor(R.id.item_title, if (done) 0xFF9A9078.toInt() else 0xFF2A2418.toInt())

        // Per-row tap targets, filled into the ListView's pending-intent template.
        // The whole row opens the app; the check/star do their silent action
        // (child taps take precedence over the row's).
        row.setOnClickFillInIntent(R.id.item_root,
            Intent().apply { data = Uri.parse("cadence://open?id=$id") })
        row.setOnClickFillInIntent(R.id.item_check,
            Intent().apply { data = Uri.parse("cadence://toggle?id=$id") })
        row.setOnClickFillInIntent(R.id.item_star,
            Intent().apply { data = Uri.parse("cadence://star?id=$id") })
        return row
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = false
}
