import 'dart:async';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final InternetConnection _internetConnection = InternetConnection();
  StreamSubscription<InternetStatus>? _subscription;
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
      final result = await _internetConnection.hasInternetAccess;
      return result;
    } catch (e) {
      return false;
    }
  }

  void startMonitoring() {
    _subscription?.cancel();
    _subscription = _internetConnection.onStatusChange.listen((InternetStatus status) {
      final hasConnection = status == InternetStatus.connected;
      _isConnected = hasConnection;
      _connectivityController.add(hasConnection);
    });
  }

  void stopMonitoring() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Called by request layers when they observe a network failure
  /// (SocketException, DNS failure, timeout). The package-level listener
  /// can lag behind real connectivity drops on some devices, so we mark
  /// offline immediately whenever a request actually fails. The next
  /// successful request — or the listener firing — will flip it back.
  void reportNetworkFailure() {
    if (!_isConnected) return;
    _isConnected = false;
    _connectivityController.add(false);
  }

  void reportNetworkSuccess() {
    if (_isConnected) return;
    _isConnected = true;
    _connectivityController.add(true);
  }

  void dispose() {
    stopMonitoring();
    _connectivityController.close();
  }
}
