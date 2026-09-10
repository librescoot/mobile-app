package de.freal.unustasis

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Bundle
import android.widget.RemoteViews

/** A read-only range snapshot. Its only action opens the app. */
class RangeWidgetReceiver : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        update(context, manager, id)
    }

    private fun update(context: Context, manager: AppWidgetManager, id: Int) {
        val data = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val range = (data.all["estimatedRangeKm"] as? Number)?.toInt()?.takeIf { it >= 0 }?.coerceAtMost(90)
        val lastPing = (data.all["lastPing"] as? Number)?.toLong()
        val age = lastPing?.let { System.currentTimeMillis() - it }
        val cached = !data.getBoolean("connected", false) || age == null || age !in 0L..60_000L
        val foreground = context.getColor(R.color.range_widget_foreground)
        val accent = context.getColor(if (cached) R.color.range_widget_muted else R.color.range_widget_accent)
        val bitmap = Bitmap.createBitmap(320, 320, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.scale(320f / 300f, 320f / 300f)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 14f
            strokeCap = Paint.Cap.ROUND
            color = context.getColor(R.color.range_widget_track)
        }
        val arc = RectF(24f, 24f, 276f, 276f)
        canvas.drawArc(arc, 135f, 270f, false, paint)
        if (range != null && range > 0) {
            paint.color = accent
            canvas.drawArc(arc, 135f, 270f * range / 90f, false, paint)
        }
        paint.style = Paint.Style.FILL
        paint.textAlign = Paint.Align.CENTER
        paint.color = foreground
        paint.typeface = Typeface.create("sans-serif", Typeface.BOLD)
        val fontScale = context.resources.configuration.fontScale.coerceAtLeast(1f)
        fun text(value: String, size: Float, baseline: Float, width: Float) {
            paint.textSize = size * fontScale
            val measured = paint.measureText(value)
            if (measured > width) paint.textSize *= width / measured
            canvas.drawText(value, 150f, baseline, paint)
        }
        text(range?.toString() ?: "—", 88f, 156f, 186f)
        paint.typeface = Typeface.create("sans-serif", Typeface.NORMAL)
        val unit = if (range != null && cached) context.getString(R.string.range_widget_saved_unit) else "km"
        text(unit, 32f, 201f, 196f)
        context.getDrawable(R.drawable.ic_bg_service_small)?.mutate()?.let {
            it.setTint(accent)
            it.setBounds(133, 240, 167, 288)
            it.draw(canvas)
        }
        val description = if (range == null) context.getString(R.string.range_widget_unavailable)
            else context.getString(R.string.range_widget_estimate, range) +
                if (cached) " " + context.getString(R.string.range_widget_cached) else ""
        val open = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val views = RemoteViews(context.packageName, R.layout.range_widget).apply {
            setImageViewBitmap(R.id.range_widget_image, bitmap)
            setContentDescription(R.id.range_widget_image, description)
            setOnClickPendingIntent(R.id.range_widget_image, PendingIntent.getActivity(
                context, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        }
        manager.updateAppWidget(id, views)
    }
}
