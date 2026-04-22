import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/app_models.dart';
import 'widget_data.dart';

class PartnerWidgetManager {
  static const String _appGroupId = 'com.lyncspace.grozfygo.widget';
  static const String _androidWidgetName = 'PartnerWidgetProvider';
  static const String _widgetDataKey = 'partner_widget_data';

  static void _log(String message) {
    debugPrint('[PartnerWidgetManager] $message');
  }

  static Future<void> initialize() async {
    _log('=== INITIALIZE START ===');
    _log('Setting AppGroupId to: $_appGroupId');
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
      _log('AppGroupId set successfully');
    } catch (e, st) {
      _log('ERROR setting AppGroupId: $e');
      _log('StackTrace: $st');
    }
    _log('=== INITIALIZE END ===');
  }

  static Future<void> updateWidget({
    required bool isOnline,
    required double todayEarnings,
    DeliveryOrder? activeOrder,
  }) async {
    _log('=== UPDATE WIDGET START ===');
    _log('Input params:');
    _log('  - isOnline: $isOnline');
    _log('  - todayEarnings: $todayEarnings');
    _log('  - activeOrder: ${activeOrder?.id ?? "null"}');

    try {
      final widgetData = PartnerWidgetData(
        isOnline: isOnline,
        todayEarnings: todayEarnings,
        activeOrderId: activeOrder?.id,
        activeOrderStatus: activeOrder?.orderStatus.label,
        lastUpdated: DateTime.now(),
      );

      final dataMap = widgetData.toMap();
      _log('WidgetData toMap(): $dataMap');

      final jsonString = jsonEncode(dataMap);
      _log('JSON encoded string (${jsonString.length} chars): $jsonString');

      _log('Step 1: Saving widget data to SharedPreferences...');
      _log('  Key: $_widgetDataKey');
      _log('  Value length: ${jsonString.length}');

      final saveResult = await HomeWidget.saveWidgetData<String>(
        _widgetDataKey,
        jsonString,
      );
      _log('saveWidgetData result: $saveResult');

      _log('Step 2: Triggering Android widget update...');
      _log('  androidWidgetName: $_androidWidgetName');

      final updateResult = await HomeWidget.updateWidget(
        name: _androidWidgetName,
        androidName: _androidWidgetName,
      );
      _log('updateWidget result: $updateResult');

      _log('Widget update completed successfully!');
    } catch (e, st) {
      _log('ERROR in updateWidget: $e');
      _log('StackTrace: $st');
    }
    _log('=== UPDATE WIDGET END ===');
  }

  static Future<PartnerWidgetData> getWidgetData() async {
    _log('=== GET WIDGET DATA START ===');
    try {
      final String? data = await HomeWidget.getWidgetData<String>(
        _widgetDataKey,
      );
      _log('Raw data from HomeWidget: ${data ?? "null"}');

      if (data == null || data.isEmpty) {
        _log('No data found, returning empty widget data');
        return PartnerWidgetData.empty();
      }

      try {
        final Map<String, dynamic> map = jsonDecode(data);
        _log('Decoded map: $map');
        return PartnerWidgetData.fromMap(map);
      } catch (e) {
        _log('ERROR decoding JSON: $e');
        return PartnerWidgetData.empty();
      }
    } catch (e) {
      _log('ERROR getting widget data: $e');
      return PartnerWidgetData.empty();
    } finally {
      _log('=== GET WIDGET DATA END ===');
    }
  }

  static Future<void> clearWidget() async {
    _log('=== CLEAR WIDGET START ===');
    try {
      _log('Saving empty string to clear data...');
      await HomeWidget.saveWidgetData<String>(_widgetDataKey, '');

      _log('Triggering widget update after clear...');
      await HomeWidget.updateWidget(
        name: _androidWidgetName,
        androidName: _androidWidgetName,
      );
      _log('Widget cleared successfully!');
    } catch (e) {
      _log('ERROR clearing widget: $e');
    }
    _log('=== CLEAR WIDGET END ===');
  }
}
