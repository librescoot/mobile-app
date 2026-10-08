package org.librescoot.watch

import android.app.PendingIntent
import android.content.Intent
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.data.*
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.concurrent.futures.CallbackToFutureAdapter
import com.google.common.util.concurrent.ListenableFuture

class ScooterTileService : TileService() {
    override fun onTileRequest(requestParams: RequestBuilders.TileRequest): ListenableFuture<TileBuilders.Tile> {
        val target = WatchStore(this).selected()
        val label = target?.optString("name") ?: "Librescoot"
        val range = if (target != null && target.has("rangeKm") && !target.isNull("rangeKm")) "≈${target.optInt("rangeKm")} km" else "Open to connect"
        val launch = ActionBuilders.LaunchAction.Builder().setAndroidActivity(
            ActionBuilders.AndroidActivity.Builder().setPackageName(packageName)
                .setClassName(WatchActivity::class.java.name).build()).build()
        val root = LayoutElementBuilders.Column.Builder()
            .setModifiers(ModifiersBuilders.Modifiers.Builder().setClickable(
                ModifiersBuilders.Clickable.Builder().setId("open").setOnClick(launch).build()).build())
            .addContent(LayoutElementBuilders.Text.Builder().setText(label).build())
            .addContent(LayoutElementBuilders.Spacer.Builder().setHeight(dp(8f)).build())
            .addContent(LayoutElementBuilders.Text.Builder().setText(range).build())
            .addContent(LayoutElementBuilders.Text.Builder().setText("Last known · tap for controls").build()).build()
        return immediate(TileBuilders.Tile.Builder().setResourcesVersion("1")
            .setTileTimeline(TimelineBuilders.Timeline.Builder().addTimelineEntry(
                TimelineBuilders.TimelineEntry.Builder().setLayout(LayoutElementBuilders.Layout.Builder().setRoot(root).build()).build()).build()).build())
    }
    override fun onTileResourcesRequest(requestParams: RequestBuilders.ResourcesRequest): ListenableFuture<ResourceBuilders.Resources> =
        immediate(ResourceBuilders.Resources.Builder().setVersion("1").build())

    private fun <T> immediate(value: T): ListenableFuture<T> = CallbackToFutureAdapter.getFuture { completer ->
        completer.set(value)
        "cached scooter tile"
    }
}

class ScooterComplicationService : ComplicationDataSourceService() {
    private fun data(preview: Boolean): ComplicationData {
        val target = if (preview) null else WatchStore(this).selected()
        val text = if (target != null && target.has("rangeKm") && !target.isNull("rangeKm")) "≈${target.optInt("rangeKm")}" else "—"
        val action = PendingIntent.getActivity(this, 0, Intent(this, WatchActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return ShortTextComplicationData.Builder(
            PlainComplicationText.Builder(text).build(),
            PlainComplicationText.Builder("Last-known scooter range in kilometres. Open for controls.").build())
            .setTitle(PlainComplicationText.Builder("km").build()).setTapAction(action).build()
    }
    override fun onComplicationRequest(request: ComplicationRequest, listener: ComplicationRequestListener) {
        listener.onComplicationData(data(false))
    }
    override fun getPreviewData(type: ComplicationType): ComplicationData = data(true)
}
