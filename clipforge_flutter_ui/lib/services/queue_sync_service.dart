import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'local_backend_api.dart';

/// Service for real-time queue synchronization via WebSocket
class QueueSyncService {
  static final QueueSyncService _instance = QueueSyncService._internal();
  factory QueueSyncService() => _instance;
  QueueSyncService._internal();

  IO.Socket? _socket;
  bool _isConnected = false;
  
  // Callbacks for job updates
  Function(Map<String, dynamic>)? onJobUpdated;
  Function(Map<String, dynamic>)? onJobCompleted;
  Function(Map<String, dynamic>)? onJobFailed;

  bool get isConnected => _isConnected;

  /// Connect to WebSocket server
  Future<void> connect() async {
    if (_isConnected) {
      print('🔌 Already connected to WebSocket');
      return;
    }

    final api = LocalBackendAPI();
    final token = api.token;
    final baseUrl = api.baseUrl;

    if (token == null) {
      print('⚠️ No auth token - cannot connect to WebSocket');
      return;
    }

    print('🔌 Connecting to WebSocket at $baseUrl');

    _socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .build(),
    );

    _socket!.onConnect((_) {
      print('✅ WebSocket connected');
      _isConnected = true;
    });

    _socket!.onDisconnect((_) {
      print('❌ WebSocket disconnected');
      _isConnected = false;
    });

    _socket!.onConnectError((error) {
      print('⚠️ WebSocket connection error: $error');
      _isConnected = false;
    });

    // Listen for job updates from server
    _socket!.on('job:updated', (data) {
      print('📊 Received job update: $data');
      onJobUpdated?.call(data as Map<String, dynamic>);
    });

    _socket!.on('job:completed', (data) {
      print('✅ Received job completion: $data');
      onJobCompleted?.call(data as Map<String, dynamic>);
    });

    _socket!.on('job:failed', (data) {
      print('❌ Received job failure: $data');
      onJobFailed?.call(data as Map<String, dynamic>);
    });

    _socket!.connect();
  }

  /// Send job progress update to server
  void sendProgress({
    required String jobId,
    required double progress,
    String status = 'processing',
  }) {
    if (!_isConnected || _socket == null) {
      print('⚠️ Cannot send progress - not connected');
      return;
    }

    _socket!.emit('job:progress', {
      'jobId': jobId,
      'progress': progress,
      'status': status,
    });
  }

  /// Send job completion to server
  void sendCompleted({
    required String jobId,
    required String outputFilename,
  }) {
    if (!_isConnected || _socket == null) {
      print('⚠️ Cannot send completion - not connected');
      return;
    }

    _socket!.emit('job:completed', {
      'jobId': jobId,
      'outputFilename': outputFilename,
    });
  }

  /// Send job failure to server
  void sendFailed({
    required String jobId,
    required String error,
  }) {
    if (!_isConnected || _socket == null) {
      print('⚠️ Cannot send failure - not connected');
      return;
    }

    _socket!.emit('job:failed', {
      'jobId': jobId,
      'error': error,
    });
  }

  /// Disconnect from WebSocket
  void disconnect() {
    if (_socket != null) {
      print('🔌 Disconnecting from WebSocket');
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _isConnected = false;
    }
  }
}
