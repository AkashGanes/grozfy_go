import 'package:flutter/foundation.dart';

class ApiLogEntry {
  const ApiLogEntry({
    required this.method,
    required this.url,
    required this.time,
  });

  final String method;
  final String url;
  final DateTime time;
}

class ApiLogStore extends ChangeNotifier {
  ApiLogStore._();

  static final ApiLogStore instance = ApiLogStore._();
  static const int _maxEntries = 200;

  final List<ApiLogEntry> _entries = <ApiLogEntry>[];

  List<ApiLogEntry> get entries => List<ApiLogEntry>.unmodifiable(_entries);

  void add({required String method, required String url}) {
    _entries.insert(
      0,
      ApiLogEntry(
        method: method.trim().toUpperCase(),
        url: url.trim(),
        time: DateTime.now(),
      ),
    );

    if (_entries.length > _maxEntries) {
      _entries.removeRange(_maxEntries, _entries.length);
    }

    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) {
      return;
    }
    _entries.clear();
    notifyListeners();
  }
}
