package com.librescoot.app

import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

class HomeWidgetReceiver : HomeWidgetGlanceWidgetReceiver<HomeWidgetGlanceAppWidget>() {
  override val glanceAppWidget = HomeWidgetGlanceAppWidget()
}
