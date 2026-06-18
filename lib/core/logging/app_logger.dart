import 'package:chirp/chirp.dart';
import 'package:flutter/foundation.dart';

/// Central logging facade backed by chirp.
///
/// Call [AppLogger.init] once at app startup (before [runApp]).
/// Each module logger is an independent [ChirpLogger] that is adopted into
/// the root on [init] so it inherits the root's writers and min-level.
abstract final class AppLogger {
  static final ChirpLogger api = ChirpLogger(name: 'api');
  static final ChirpLogger fcm = ChirpLogger(name: 'fcm');
  static final ChirpLogger location = ChirpLogger(name: 'location');
  static final ChirpLogger sync = ChirpLogger(name: 'sync');
  static final ChirpLogger offlineTrip = ChirpLogger(name: 'offline_trip');
  static final ChirpLogger auth = ChirpLogger(name: 'auth');
  static final ChirpLogger notification = ChirpLogger(name: 'notification');
  static final ChirpLogger app = ChirpLogger(name: 'app');
  static final ChirpLogger widget = ChirpLogger(name: 'widget');

  static void init() {
    Chirp.root = ChirpLogger()
        .addConsoleWriter(
          formatter: RainbowMessageFormatter(),
          minLogLevel:
              kDebugMode ? ChirpLogLevel.debug : ChirpLogLevel.warning,
        );

    Chirp.root
      ..adopt(api)
      ..adopt(fcm)
      ..adopt(location)
      ..adopt(sync)
      ..adopt(offlineTrip)
      ..adopt(auth)
      ..adopt(notification)
      ..adopt(app)
      ..adopt(widget);
  }
}
