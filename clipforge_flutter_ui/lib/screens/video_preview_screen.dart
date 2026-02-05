import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../services/local_backend_api.dart';
import '../services/gallery_export_service.dart';

class VideoPreviewScreen extends StatefulWidget {
  const VideoPreviewScreen({
    super.key,
    required this.videoPath,
    required this.title,
  });

  final String videoPath;
  final String title;

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  String? _error;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final resolved = LocalBackendAPI().resolveMediaUrl(widget.videoPath);
      final controller =
          resolved.startsWith('http://') || resolved.startsWith('https://')
              ? VideoPlayerController.networkUrl(Uri.parse(resolved))
              : VideoPlayerController.file(File(resolved));
      await controller.initialize();
      await controller.play();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadVideo() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final resolved = LocalBackendAPI().resolveMediaUrl(widget.videoPath);
      String localPath = resolved;
      if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Downloading video...')),
        );
        final client = http.Client();
        try {
          final response =
              await client.send(http.Request('GET', Uri.parse(resolved)));
          if (response.statusCode != 200) {
            throw Exception('Download failed (${response.statusCode})');
          }
          final dir = await getTemporaryDirectory();
          final filePath =
              '${dir.path}/clipforge_${DateTime.now().millisecondsSinceEpoch}.mp4';
          final file = File(filePath);
          final sink = file.openWrite();
          await response.stream.pipe(sink);
          await sink.flush();
          await sink.close();
          localPath = file.path;
        } finally {
          client.close();
        }
      }

      final saved = await GalleryExportService().saveVideoToGallery(localPath);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            saved ? 'Saved to gallery.' : 'Could not save to gallery.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _isDownloading ? null : _downloadVideo,
            icon: _isDownloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            tooltip: 'Download',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        VideoPlayer(_controller!),
                        VideoProgressIndicator(
                          _controller!,
                          allowScrubbing: true,
                        ),
                      ],
                    ),
                  ),
                ),
      floatingActionButton:
          (_controller != null && _controller!.value.isInitialized)
              ? FloatingActionButton(
                  onPressed: () {
                    final c = _controller!;
                    if (c.value.isPlaying) {
                      c.pause();
                    } else {
                      c.play();
                    }
                    setState(() {});
                  },
                  child: Icon(_controller!.value.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow),
                )
              : null,
    );
  }
}
