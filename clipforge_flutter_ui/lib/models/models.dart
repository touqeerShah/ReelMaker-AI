import 'package:flutter/material.dart';

enum ProjectStatus { draft, processing, completed, failed }

enum JobStage {
  queued,
  extractingAudio,
  transcribing,
  translating,
  dubbing,
  rendering,
  completed,
  failed,
}

class Project {
  Project({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.duration,
    required this.status,
    required this.thumbnail,
    required this.shortsCount,
    required this.languages,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final Duration duration;
  final ProjectStatus status;
  final String thumbnail;
  final int shortsCount;
  final List<String> languages;
}

class Job {
  Job({
    required this.id,
    required this.title,
    required this.thumbnail,
    required this.stage,
    required this.progress,
    required this.elapsed,
    this.speed = 1.0,
    this.eta,
    this.hasDeviceHotWarning = false,
    this.hasLowBatteryWarning = false,
  });

  final String id;
  final String title;
  final String thumbnail;
  final JobStage stage;
  final double progress; // 0..1
  final Duration elapsed;
  final double speed;
  final Duration? eta;
  final bool hasDeviceHotWarning;
  final bool hasLowBatteryWarning;
}

class ModelAsset {
  ModelAsset({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.sizeLabel,
    required this.icon,
    required this.status,
  });

  final String id;
  final String name;
  final String subtitle;
  final String sizeLabel;
  final IconData icon;
  final ModelStatus status;
}

enum ModelStatus { notInstalled, downloading, ready, updateAvailable }

String projectStatusLabel(ProjectStatus s) => switch (s) {
      ProjectStatus.draft => 'Draft',
      ProjectStatus.processing => 'Processing',
      ProjectStatus.completed => 'Completed',
      ProjectStatus.failed => 'Failed',
    };

Color projectStatusColor(ProjectStatus s, ColorScheme cs) => switch (s) {
      ProjectStatus.draft => cs.outline,
      ProjectStatus.processing => cs.primary,
      ProjectStatus.completed => Colors.green,
      ProjectStatus.failed => Colors.red,
    };

String jobStageLabel(JobStage s) => switch (s) {
      JobStage.queued => 'Queued',
      JobStage.extractingAudio => 'Extracting audio',
      JobStage.transcribing => 'Transcribing',
      JobStage.translating => 'Translating',
      JobStage.dubbing => 'Dubbing',
      JobStage.rendering => 'Rendering',
      JobStage.completed => 'Completed',
      JobStage.failed => 'Failed',
    };
