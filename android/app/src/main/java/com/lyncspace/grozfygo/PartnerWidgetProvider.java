package com.lyncspace.grozfygo;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.widget.RemoteViews;

import org.json.JSONObject;

import java.util.Locale;

import es.antonborri.home_widget.HomeWidgetPlugin;

public class PartnerWidgetProvider extends AppWidgetProvider {
  public static void updateAppWidget(
      Context context,
      AppWidgetManager appWidgetManager,
      int appWidgetId
  ) {
    RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.partner_widget);

    android.content.SharedPreferences widgetData = HomeWidgetPlugin.Companion.getData(context);
    String widgetString = widgetData.getString("partner_widget_data", "");
    if (widgetString == null) {
      widgetString = "";
    }

    if (!widgetString.isEmpty()) {
      try {
        JSONObject json = new JSONObject(widgetString);
        boolean isOnline = json.optBoolean("isOnline", false);
        double todayEarnings = json.optDouble("todayEarnings", 0.0);
        String activeOrderId = json.optString("activeOrderId", "");
        String activeOrderStatus = json.optString("activeOrderStatus", "");

        String statusColor = isOnline ? "#4CAF50" : "#F44336";
        views.setInt(
            R.id.widget_status_icon,
            "setBackgroundColor",
            Color.parseColor(statusColor)
        );
        views.setTextViewText(R.id.widget_status_text, isOnline ? "Online" : "Offline");
        views.setTextViewText(
            R.id.widget_earnings,
            "Rs. " + String.format(Locale.US, "%.0f", todayEarnings)
        );

        if (!activeOrderId.isEmpty()) {
          views.setTextViewText(
              R.id.widget_order_status,
              activeOrderId + " · " + activeOrderStatus
          );
        } else {
          views.setTextViewText(R.id.widget_order_status, "No active order");
        }
      } catch (Exception ignored) {
        views.setTextViewText(R.id.widget_status_text, "Error");
        views.setTextViewText(R.id.widget_earnings, "Rs. 0");
        views.setTextViewText(R.id.widget_order_status, "Tap to open");
      }
    } else {
      views.setTextViewText(R.id.widget_status_text, "Offline");
      views.setTextViewText(R.id.widget_earnings, "Rs. 0");
      views.setTextViewText(R.id.widget_order_status, "Open app to update");
    }

    Intent intent = new Intent(context, MainActivity.class);
    intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
    PendingIntent pendingIntent = PendingIntent.getActivity(
        context,
        0,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
    );
    views.setOnClickPendingIntent(R.id.widget_container, pendingIntent);

    appWidgetManager.updateAppWidget(appWidgetId, views);
  }

  @Override
  public void onUpdate(
      Context context,
      AppWidgetManager appWidgetManager,
      int[] appWidgetIds
  ) {
    for (int appWidgetId : appWidgetIds) {
      updateAppWidget(context, appWidgetManager, appWidgetId);
    }
  }
}
