package com.example.delivery_partner_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONObject

class PartnerWidgetProvider : AppWidgetProvider() {
    companion object {
        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.partner_widget)

            val widgetData = HomeWidgetPlugin.getData(context)
            val widgetString = widgetData.getString("partner_widget_data", "") ?: ""

            if (widgetString.isNotEmpty()) {
                try {
                    val json = JSONObject(widgetString)
                    val isOnline = json.optBoolean("isOnline", false)
                    val todayEarnings = json.optDouble("todayEarnings", 0.0)
                    val activeOrderId = json.optString("activeOrderId", "")
                    val activeOrderStatus = json.optString("activeOrderStatus", "")

                    val statusColor = if (isOnline) "#4CAF50" else "#F44336"
                    views.setInt(R.id.widget_status_icon, "setBackgroundColor", android.graphics.Color.parseColor(statusColor))
                    views.setTextViewText(R.id.widget_status_text, if (isOnline) "Online" else "Offline")

                    views.setTextViewText(
                        R.id.widget_earnings,
                        "Rs. ${String.format("%.0f", todayEarnings)}"
                    )

                    if (activeOrderId.isNotEmpty()) {
                        views.setTextViewText(
                            R.id.widget_order_status,
                            "$activeOrderId · $activeOrderStatus"
                        )
                    } else {
                        views.setTextViewText(R.id.widget_order_status, "No active order")
                    }
                } catch (e: Exception) {
                    views.setTextViewText(R.id.widget_status_text, "Error")
                    views.setTextViewText(R.id.widget_earnings, "Rs. 0")
                    views.setTextViewText(R.id.widget_order_status, "Tap to open")
                }
            } else {
                views.setTextViewText(R.id.widget_status_text, "Offline")
                views.setTextViewText(R.id.widget_earnings, "Rs. 0")
                views.setTextViewText(R.id.widget_order_status, "Open app to update")
            }

            val intent = Intent(context, MainActivity::class.java)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }
}
