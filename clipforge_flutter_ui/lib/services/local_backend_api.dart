import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Local backend API service for authentication, video upload, and queue management
class LocalBackendAPI {
  // Default to Mac IP from ifconfig - user can change in settings
  static const String defaultBaseUrl = 'http://10.143.187.74:4000';

  String _baseUrl = defaultBaseUrl;
  String? _token;

  // Public getters
  String get baseUrl => _baseUrl;
  String? get token => _token;
  bool get isAuthenticated => _token != null;

  // Singleton pattern
  static final LocalBackendAPI _instance = LocalBackendAPI._internal();
  factory LocalBackendAPI() => _instance;
  LocalBackendAPI._internal();

  /// Initialize and load saved settings
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('backend_url') ?? defaultBaseUrl;
    _token = prefs.getString('auth_token');
  }

  /// Save backend URL
  Future<void> setBackendUrl(String url) async {
    _baseUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_url', url);
  }

  /// Get current backend URL
  String get backendUrl => _baseUrl;

  /// Resolve a media URL for playback/thumbnail
  /// - Fixes localhost/127.0.0.1 when running on device
  /// - Expands /uploads paths with backend base URL
  /// - Strips file:// for local paths
  String resolveMediaUrl(String raw) {
    if (raw.isEmpty) return raw;
    if (raw.startsWith('file://')) return raw.substring(7);

    final trimmed = raw.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
        final base = Uri.tryParse(_baseUrl);
        if (base != null && base.host.isNotEmpty) {
          return uri
              .replace(
                scheme: base.scheme,
                host: base.host,
                port: base.hasPort ? base.port : null,
              )
              .toString();
        }
      }
      return trimmed;
    }

    if (trimmed.startsWith('/uploads/')) {
      final base = Uri.tryParse(_baseUrl);
      if (base != null && base.host.isNotEmpty) {
        return base
            .replace(
              path: trimmed,
              query: null,
              fragment: null,
            )
            .toString();
      }
      final baseStr = _baseUrl.replaceAll(RegExp(r'/+$'), '');
      return '$baseStr$trimmed';
    }

    return trimmed;
  }

  /// Save auth token
  Future<void> _saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  /// Clear auth token
  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  // ============ Auth Endpoints ============

  /// Register new user
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String? name,
  }) async {
    try {
      final url = '$_baseUrl/api/auth/register';
      print('🔵 REGISTER: Attempting to connect to: $url');

      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'password': password,
              if (name != null) 'name': name,
            }),
          )
          .timeout(const Duration(seconds: 10));

      print('🔵 REGISTER: Response status: ${response.statusCode}');
      print('🔵 REGISTER: Response body: ${response.body}');

      if (response.statusCode == 201) {
        if (response.body.isEmpty) {
          throw Exception('Empty response from server');
        }
        final data = jsonDecode(response.body);
        await _saveToken(data['token']);
        return data;
      } else {
        if (response.body.isEmpty) {
          throw Exception('Server error (${response.statusCode})');
        }
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Registration failed');
      }
    } on SocketException catch (e) {
      print('🔴 REGISTER: SocketException: $e');
      throw Exception(
          'Cannot connect to server at $_baseUrl. Make sure backend is running.');
    } on FormatException catch (e) {
      print('🔴 REGISTER: FormatException: $e');
      throw Exception('Invalid response from server: ${e.message}');
    } on TimeoutException catch (e) {
      print('🔴 REGISTER: TimeoutException: $e');
      throw Exception('Connection timeout - server not responding');
    } catch (e) {
      print('🔴 REGISTER: Generic error: $e');
      throw Exception('Network error: $e');
    }
  }

  /// Login user
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          throw Exception('Empty response from server');
        }
        final data = jsonDecode(response.body);
        await _saveToken(data['token']);
        return data;
      } else {
        if (response.body.isEmpty) {
          throw Exception('Server error (${response.statusCode})');
        }
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Login failed');
      }
    } on SocketException {
      throw Exception('Cannot connect to server. Check network connection.');
    } on FormatException catch (e) {
      throw Exception('Invalid response from server: ${e.message}');
    } on TimeoutException {
      throw Exception('Connection timeout - server not responding');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Get current user info
  Future<Map<String, dynamic>> getCurrentUser() async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$_baseUrl/api/auth/me'),
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get user info');
    }
  }

  /// Logout
  Future<void> logout() async {
    await clearToken();
  }

  // ============ Video Endpoints ============

  /// Create video metadata (no file upload - video stays on phone)
  Future<Map<String, dynamic>> createVideoMetadata({
    required String title,
    required double durationSec,
    String? resolution,
    String? localPath,
    int? segmentDuration,
    double? overlayDuration,
    String? logoPosition,
    bool? watermarkEnabled,
    double? watermarkAlpha,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$_baseUrl/api/videos/metadata'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'title': title,
        'durationSec': durationSec,
        if (resolution != null) 'resolution': resolution,
        if (localPath != null) 'localPath': localPath,
        if (segmentDuration != null) 'segmentDuration': segmentDuration,
        if (overlayDuration != null) 'overlayDuration': overlayDuration,
        if (logoPosition != null) 'logoPosition': logoPosition,
        if (watermarkEnabled != null) 'watermarkEnabled': watermarkEnabled,
        if (watermarkAlpha != null) 'watermarkAlpha': watermarkAlpha,
      }),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to create video metadata');
    }
  }

  /// Upload video (deprecated - keeping for backward compatibility)
  Future<Map<String, dynamic>> uploadVideo({
    required File videoFile,
    required String title,
    double? durationSec,
    String? resolution,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/api/videos/upload'),
    );

    request.headers['Authorization'] = 'Bearer $_token';
    request.fields['title'] = title;
    if (durationSec != null)
      request.fields['durationSec'] = durationSec.toString();
    if (resolution != null) request.fields['resolution'] = resolution;

    request.files
        .add(await http.MultipartFile.fromPath('video', videoFile.path));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Video upload failed');
    }
  }

  /// Upload video in chunks with progress (backend pipeline)
  Future<Map<String, dynamic>> uploadVideoChunked({
    required File videoFile,
    required String title,
    double? durationSec,
    String? resolution,
    int chunkSizeBytes = 4 * 1024 * 1024,
    int maxRetries = 3,
    int parallelUploads = 3,
    bool shuffleParts = false,
    void Function(double progress, int sentBytes, int totalBytes)? onProgress,
    void Function(int partIndex, int totalParts)? onChunk,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final totalBytes = await videoFile.length();
    final totalParts = (totalBytes / chunkSizeBytes).ceil();
    final safeParallel = parallelUploads <= 0 ? 1 : parallelUploads;

    final client = http.Client();
    final initResp = await client.post(
      Uri.parse('$_baseUrl/api/uploads/init'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'filename': title,
        'sizeBytes': totalBytes,
        'totalParts': totalParts,
        'chunkSize': chunkSizeBytes,
      }),
    );

    if (initResp.statusCode != 200) {
      final error = jsonDecode(initResp.body);
      client.close();
      throw Exception(error['error'] ?? 'Failed to init upload');
    }
    final initData = jsonDecode(initResp.body) as Map<String, dynamic>;
    final uploadId = initData['uploadId']?.toString();
    if (uploadId == null || uploadId.isEmpty) {
      client.close();
      throw Exception('Upload ID missing from backend');
    }

    int sent = 0;
    int completedParts = 0;
    bool cancelled = false;
    try {
      final indices =
          List<int>.generate(totalParts, (index) => index, growable: false);
      if (shuffleParts) {
        indices.shuffle();
      }
      final queue = Queue<int>.from(indices);

      Future<void> worker() async {
        while (true) {
          if (cancelled) return;
          if (queue.isEmpty) return;
          final partIndex = queue.removeFirst();
          final offset = partIndex * chunkSizeBytes;
          final remaining = totalBytes - offset;
          final readSize = min(chunkSizeBytes, remaining);
          onChunk?.call(partIndex + 1, totalParts);

          int attempt = 0;
          while (true) {
            attempt += 1;
            try {
              final raf = await videoFile.open();
              try {
                await raf.setPosition(offset);
                final bytes = await raf.read(readSize);

                final req = http.MultipartRequest(
                  'POST',
                  Uri.parse('$_baseUrl/api/uploads/part'),
                );
                req.headers['Authorization'] = 'Bearer $_token';
                req.fields['uploadId'] = uploadId;
                req.fields['partIndex'] = partIndex.toString();
                req.fields['totalParts'] = totalParts.toString();
                req.files.add(http.MultipartFile.fromBytes(
                  'chunk',
                  bytes,
                  filename: 'chunk_$partIndex',
                ));

                final streamed =
                    await client.send(req).timeout(const Duration(minutes: 2));
                final resp = await http.Response.fromStream(streamed);
                if (resp.statusCode != 200) {
                  final error = jsonDecode(resp.body);
                  throw Exception(error['error'] ?? 'Chunk upload failed');
                }

                sent += bytes.length;
                completedParts += 1;
                if (onProgress != null) {
                  onProgress(sent / totalBytes, sent, totalBytes);
                }
                break;
              } finally {
                await raf.close();
              }
            } catch (e) {
              if (attempt >= maxRetries) {
                cancelled = true;
                rethrow;
              }
              await Future.delayed(Duration(milliseconds: 600 * attempt));
            }
          }
        }
      }

      final workers = List.generate(
        min(safeParallel, totalParts),
        (_) => worker(),
      );
      await Future.wait(workers);

      if (completedParts != totalParts) {
        throw Exception('Upload incomplete: $completedParts/$totalParts parts');
      }
    } finally {
      // no-op
    }

    final completeResp = await client.post(
      Uri.parse('$_baseUrl/api/uploads/complete'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'uploadId': uploadId,
        'title': title,
        if (durationSec != null) 'durationSec': durationSec,
        if (resolution != null) 'resolution': resolution,
      }),
    );

    if (completeResp.statusCode != 201 && completeResp.statusCode != 200) {
      final error = jsonDecode(completeResp.body);
      client.close();
      throw Exception(error['error'] ?? 'Failed to finalize upload');
    }
    final result = jsonDecode(completeResp.body);
    client.close();
    return result;
  }

  /// Get all videos
  Future<List<dynamic>> getVideos() async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$_baseUrl/api/videos'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['videos'];
    } else {
      throw Exception('Failed to fetch videos');
    }
  }

  /// Get video by ID
  Future<Map<String, dynamic>> getVideo(String videoId) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$_baseUrl/api/videos/$videoId'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['video'];
    } else {
      throw Exception('Failed to fetch video');
    }
  }

  /// Delete video
  Future<void> deleteVideo(String videoId) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.delete(
      Uri.parse('$_baseUrl/api/videos/$videoId'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete video');
    }
  }

  // ============ Queue Endpoints ============

  /// Create processing job
  Future<Map<String, dynamic>> createJob({
    required String videoId,
    int? chunkIndex,
    String? outputFilename,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$_baseUrl/api/queue/jobs'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'videoId': videoId,
        if (chunkIndex != null) 'chunkIndex': chunkIndex,
        if (outputFilename != null) 'outputFilename': outputFilename,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['job'];
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to create job');
    }
  }

  /// Get jobs with optional filters
  Future<List<dynamic>> getJobs({
    String? videoId,
    String? projectId,
    String? status,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final queryParams = <String, String>{};
    if (videoId != null) queryParams['videoId'] = videoId;
    if (projectId != null) queryParams['projectId'] = projectId;
    if (status != null) queryParams['status'] = status;

    final uri = Uri.parse('$_baseUrl/api/queue/jobs')
        .replace(queryParameters: queryParams);

    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['jobs'];
    } else {
      throw Exception('Failed to fetch jobs');
    }
  }

  Future<Map<String, dynamic>> getSummaryCandidates(String projectId) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$_baseUrl/api/projects/$projectId/summary-candidates'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      if (response.body.isEmpty) {
        throw Exception('Empty response from server');
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to load summary candidates');
  }

  Future<void> submitSummarySelection({
    required String projectId,
    required String jobId,
    required List<Map<String, dynamic>> selected,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$_baseUrl/api/projects/$projectId/summary-selection'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'jobId': jobId,
        'selected': selected,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to submit selection');
    }
  }

  /// Get single job by ID
  Future<Map<String, dynamic>> getJob(String jobId) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$_baseUrl/api/queue/jobs/$jobId'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['job'] as Map<String, dynamic>;
    } else {
      throw Exception('Failed to fetch job');
    }
  }

  /// Update job status/progress
  Future<Map<String, dynamic>> updateJob({
    required String jobId,
    String? status,
    double? progress,
    String? errorMessage,
    String? outputFilename,
    String? outputPath,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.patch(
      Uri.parse('$_baseUrl/api/queue/jobs/$jobId'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        if (status != null) 'status': status,
        if (progress != null) 'progress': progress,
        if (errorMessage != null) 'errorMessage': errorMessage,
        if (outputFilename != null) 'outputFilename': outputFilename,
        if (outputPath != null) 'outputPath': outputPath,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['job'];
    } else {
      throw Exception('Failed to update job');
    }
  }

  /// Delete job
  Future<void> deleteJob(String jobId) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.delete(
      Uri.parse('$_baseUrl/api/queue/jobs/$jobId'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete job');
    }
  }

  // ============ Project Endpoints ============

  /// Create new project
  Future<Map<String, dynamic>> createProject({
    required String videoId,
    required String title,
    required int totalChunks,
    Map<String, dynamic>? settings,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$_baseUrl/api/projects'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'videoId': videoId,
        'title': title,
        'totalChunks': totalChunks,
        if (settings != null) 'settings': settings,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['project'];
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to create project');
    }
  }

  /// Create new project with jobs in one transaction
  Future<Map<String, dynamic>> createProjectWithJobs({
    required String videoId,
    required String title,
    required int totalChunks,
    required List<Map<String, dynamic>> jobs,
    Map<String, dynamic>? settings,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$_baseUrl/api/projects'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'videoId': videoId,
        'title': title,
        'totalChunks': totalChunks,
        'jobs': jobs,
        if (settings != null) 'settings': settings,
      }),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body); // Returns { project: ..., jobs: [...] }
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to create project with jobs');
    }
  }

  /// Create multiple jobs in batch
  Future<List<dynamic>> createBatchJobs(List<Map<String, dynamic>> jobs) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$_baseUrl/api/queue/jobs/batch'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'jobs': jobs,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['jobs'];
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to create batch jobs');
    }
  }

  /// Get all projects
  Future<List<dynamic>> getProjects({String? status}) async {
    if (_token == null) throw Exception('Not authenticated');

    final queryParams = <String, String>{};
    if (status != null) queryParams['status'] = status;

    final uri = Uri.parse('$_baseUrl/api/projects')
        .replace(queryParameters: queryParams);

    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['projects'];
    } else {
      throw Exception('Failed to fetch projects');
    }
  }

  /// Get single project by ID
  Future<Map<String, dynamic>> getProject(String projectId) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$_baseUrl/api/projects/$projectId'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['project'];
    } else {
      throw Exception('Failed to fetch project');
    }
  }

  /// Get project statistics
  Future<Map<String, dynamic>> getProjectStats(String projectId) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$_baseUrl/api/projects/$projectId/stats'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch project stats');
    }
  }

  /// Update project
  Future<Map<String, dynamic>> updateProject({
    required String projectId,
    String? status,
    int? completedChunks,
    int? failedChunks,
    double? progress,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.patch(
      Uri.parse('$_baseUrl/api/projects/$projectId'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        if (status != null) 'status': status,
        if (completedChunks != null) 'completedChunks': completedChunks,
        if (failedChunks != null) 'failedChunks': failedChunks,
        if (progress != null) 'progress': progress,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['project'];
    } else {
      throw Exception('Failed to update project');
    }
  }

  /// Delete project
  Future<void> deleteProject(String projectId) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.delete(
      Uri.parse('$_baseUrl/api/projects/$projectId'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete project');
    }
  }

  // ============ Output Video Endpoints ============

  /// Register a new output video after split processing
  Future<Map<String, dynamic>> registerOutputVideo({
    required String projectId,
    required String jobId,
    required int chunkIndex,
    required String filename,
    String? filePath,
    double? durationSec,
    int? sizeBytes,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$_baseUrl/api/outputs'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'projectId': projectId,
        'jobId': jobId,
        'chunkIndex': chunkIndex,
        'filename': filename,
        if (filePath != null) 'filePath': filePath,
        if (durationSec != null) 'durationSec': durationSec,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['output'];
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to register output video');
    }
  }

  /// Get all output videos for a project
  Future<List<dynamic>> getProjectOutputs(String projectId) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$_baseUrl/api/outputs/$projectId'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['outputs'];
    } else {
      throw Exception('Failed to fetch project outputs');
    }
  }

  /// Delete a specific output video
  Future<void> deleteOutput(String outputId) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.delete(
      Uri.parse('$_baseUrl/api/outputs/$outputId'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete output');
    }
  }

  /// Re-render project with new settings
  Future<Map<String, dynamic>> reRenderProject({
    required String projectId,
    required Map<String, dynamic> settings,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$_baseUrl/api/projects/$projectId/re-render'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'settings': settings,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to re-render project');
    }
  }

  /// Analyze one transcript chunk for AI best-scenes
  Future<Map<String, dynamic>> analyzeAiBestScenesChunk({
    required int chunkIndex,
    required List<Map<String, dynamic>> items,
    String? contextText,
    double minSceneSec = 20,
    double maxSceneSec = 55,
    int segmentsPerChunk = 1,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$_baseUrl/api/ai/best-scenes/analyze'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'chunkIndex': chunkIndex,
        'items': items,
        if (contextText != null && contextText.isNotEmpty)
          'contextText': contextText,
        'minSceneSec': minSceneSec,
        'maxSceneSec': maxSceneSec,
        'segmentsPerChunk': segmentsPerChunk,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(
          error['error'] ?? 'Failed to analyze AI best scenes chunk');
    }
  }

  Future<List<Map<String, dynamic>>> getAiChunkCache({
    required String projectId,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$_baseUrl/api/ai/best-scenes/chunks/$projectId'),
      headers: {'Authorization': 'Bearer $_token'},
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final chunks = (data['chunks'] as List<dynamic>? ?? const []);
      return chunks.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    throw Exception('Failed to fetch AI chunk cache');
  }

  Future<void> saveAiChunkCache({
    required String projectId,
    required int chunkIndex,
    required List<Map<String, dynamic>> chunkInput,
    required List<Map<String, dynamic>> segments,
    String contextText = '',
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('$_baseUrl/api/ai/best-scenes/chunks'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'projectId': projectId,
        'chunkIndex': chunkIndex,
        'chunkInput': chunkInput,
        'contextText': contextText,
        'segments': segments,
      }),
    );
    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to save AI chunk cache');
    }
  }

  /// Upload extracted audio and transcribe to SRT via backend whisper-cli
  Future<String> transcribeAudioToSrt({
    required String audioPath,
  }) async {
    if (_token == null) throw Exception('Not authenticated');

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/api/ai/transcribe-audio'),
    );
    request.headers['Authorization'] = 'Bearer $_token';
    request.files.add(await http.MultipartFile.fromPath('audio', audioPath));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final srt = data['srt']?.toString() ?? '';
      if (srt.isEmpty) {
        throw Exception('Empty transcript returned by backend');
      }
      return srt;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Failed to transcribe audio');
    }
  }

  /// Get overall queue statistics
  Future<Map<String, dynamic>> getQueueStats() async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$_baseUrl/api/queue/stats'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['stats'];
    } else {
      throw Exception('Failed to fetch queue stats');
    }
  }

  /// Get queue statistics for specific video
  Future<Map<String, dynamic>> getVideoQueueStats(String videoId) async {
    if (_token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$_baseUrl/api/queue/stats/$videoId'),
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['stats'];
    } else {
      throw Exception('Failed to fetch video queue stats');
    }
  }

  /// Test connection to backend
  Future<bool> testConnection() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
