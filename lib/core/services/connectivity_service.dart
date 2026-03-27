import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final StreamController<bool> _connectivityController =
      StreamController<bool>.broadcast();

  Stream<bool> get connectivityStream => _connectivityController.stream;
  bool _isConnected = true;
  bool get isConnected => _isConnected;

  Future<void> initialize() async {
    final result = await checkConnectivity();
    _isConnected = result;
    _connectivityController.add(result);
  }

  Future<bool> checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return _hasConnection(results);
    } catch (e) {
      return false;
    }
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((result) =>
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet);
  }

  void startMonitoring() {
    _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final hasConnection = _hasConnection(results);
      _isConnected = hasConnection;
      _connectivityController.add(hasConnection);
    });
  }

  void stopMonitoring() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stopMonitoring();
    _connectivityController.close();
  }
}
