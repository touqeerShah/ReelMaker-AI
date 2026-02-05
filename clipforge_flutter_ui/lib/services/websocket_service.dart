import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;

/// WebSocket service for real-time updates using Socket.IO
class WebSocketService {
  IO.Socket? _socket;
  String? _token;
  String? _baseUrl;
  
  // Stream controllers for different event types
  final _jobUpdatedController = StreamController<Map<String, dynamic>>.broadcast();
  final _jobCreatedController = StreamController<Map<String, dynamic>>.broadcast();
  final _jobCompletedController = StreamController<Map<String, dynamic>>.broadcast();
  final _jobFailedController = StreamController<Map<String, dynamic>>.broadcast();
  final _projectUpdatedController = StreamController<Map<String, dynamic>>.broadcast();
  final _projectCreatedController = StreamController<Map<String, dynamic>>.broadcast();
  final _projectDeletedController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();

  // Public streams
  Stream<Map<String, dynamic>> get jobUpdatedStream => _jobUpdatedController.stream;
  Stream<Map<String, dynamic>> get jobCreatedStream => _jobCreatedController.stream;
  Stream<Map<String, dynamic>> get jobCompletedStream => _jobCompletedController.stream;
  Stream<Map<String, dynamic>> get jobFailedStream => _jobFailedController.stream;
  Stream<Map<String, dynamic>> get projectUpdatedStream => _projectUpdatedController.stream;
  Stream<Map<String, dynamic>> get projectCreatedStream => _projectCreatedController.stream;
  Stream<Map<String, dynamic>> get projectDeletedStream => _projectDeletedController.stream;
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  bool get isConnected => _socket?.connected ?? false;

  // Singleton pattern
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  /// Connect to WebSocket server
  void connect(String baseUrl, String token) {
    _baseUrl = baseUrl;
    _token = token;

    // Disconnect if already connected
    disconnect();

    print('🔌 WebSocket: Connecting to $baseUrl');

    _socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setReconnectionAttempts(5)
          .setAuth({'token': token})
          .build(),
    );

    // Connection events
    _socket!.onConnect((_) {
      print('🔌 WebSocket: Connected');
      _connectionStatusController.add(true);
    });

    _socket!.onDisconnect((_) {
      print('🔌 WebSocket: Disconnected');
      _connectionStatusController.add(false);
    });

    _socket!.onConnectError((error) {
      print('🔌 WebSocket: Connection error: $error');
      _connectionStatusController.add(false);
    });

    _socket!.onError((error) {
      print('🔌 WebSocket: Error: $error');
    });

    // Job events
    _socket!.on('job:created', (data) {
      print('📨 WebSocket: job:created received');
      _jobCreatedController.add(data as Map<String, dynamic>);
    });

    _socket!.on('job:updated', (data) {
      print('📨 WebSocket: job:updated received');
      _jobUpdatedController.add(data as Map<String, dynamic>);
    });

    _socket!.on('job:completed', (data) {
      print('📨 WebSocket: job:completed received');
      _jobCompletedController.add(data as Map<String, dynamic>);
    });

    _socket!.on('job:failed', (data) {
      print('📨 WebSocket: job:failed received');
      _jobFailedController.add(data as Map<String, dynamic>);
    });

    // Project events
    _socket!.on('project:created', (data) {
      print('📨 WebSocket: project:created received');
      _projectCreatedController.add(data as Map<String, dynamic>);
    });

    _socket!.on('project:updated', (data) {
      print('📨 WebSocket: project:updated received');
      _projectUpdatedController.add(data as Map<String, dynamic>);
    });

    _socket!.on('project:deleted', (data) {
      print('📨 WebSocket: project:deleted received');
      _projectDeletedController.add(data as Map<String, dynamic>);
    });

    _socket!.connect();
  }

  /// Emit job progress update
  void emitJobProgress(String jobId, double progress, String status) {
    if (_socket?.connected == true) {
      _socket!.emit('job:progress', {
        'jobId': jobId,
        'progress': progress,
        'status': status,
      });
      print('📤 WebSocket: Emitted job:progress for $jobId');
    }
  }

  /// Emit job completion
  void emitJobCompleted(String jobId, String outputFilename) {
    if (_socket?.connected == true) {
      _socket!.emit('job:completed', {
        'jobId': jobId,
        'outputFilename': outputFilename,
      });
      print('📤 WebSocket: Emitted job:completed for $jobId');
    }
  }

  /// Emit job failure
  void emitJobFailed(String jobId, String error) {
    if (_socket?.connected == true) {
      _socket!.emit('job:failed', {
        'jobId': jobId,
        'error': error,
      });
      print('📤 WebSocket: Emitted job:failed for $jobId');
    }
  }

  /// Disconnect from WebSocket server
  void disconnect() {
    if (_socket != null) {
      print('🔌 WebSocket: Disconnecting');
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _connectionStatusController.add(false);
    }
  }

  /// Dispose all resources
  void dispose() {
    disconnect();
    _jobUpdatedController.close();
    _jobCreatedController.close();
    _jobCompletedController.close();
    _jobFailedController.close();
    _projectUpdatedController.close();
    _projectCreatedController.close();
    _projectDeletedController.close();
    _connectionStatusController.close();
  }
}
