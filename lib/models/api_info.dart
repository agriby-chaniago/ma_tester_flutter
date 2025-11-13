/// Model untuk data API/Server Info (Tabel 1)
class ApiInfo {
  final String apiVersion;
  final String modelVersion;
  final String checkpointSha256;
  final String device;
  final double? warmupMs;
  final double serverUptimeS;
  final String flutterBuild;
  final String deviceModel;
  final String networkType;

  ApiInfo({
    required this.apiVersion,
    required this.modelVersion,
    required this.checkpointSha256,
    required this.device,
    this.warmupMs,
    required this.serverUptimeS,
    required this.flutterBuild,
    required this.deviceModel,
    required this.networkType,
  });

  factory ApiInfo.fromJson(Map<String, dynamic> json) {
    return ApiInfo(
      apiVersion: json['api_version'] ?? 'N/A',
      modelVersion: json['model_version'] ?? 'N/A',
      checkpointSha256: json['checkpoint_sha256'] ?? 'N/A',
      device: json['device'] ?? 'N/A',
      warmupMs: json['warmup_ms']?.toDouble(),
      serverUptimeS: (json['uptime_s'] ?? 0).toDouble(),
      flutterBuild: 'N/A', // Will be set from Flutter side
      deviceModel: 'N/A', // Will be set from Flutter side
      networkType: 'N/A', // Will be set from Flutter side
    );
  }

  Map<String, String> toTableData() {
    return {
      'API Version': apiVersion,
      'Model Version': modelVersion,
      'Checkpoint SHA-256': checkpointSha256,
      'Device': device,
      'Warmup (ms)': warmupMs?.toStringAsFixed(2) ?? 'N/A',
      'Server Uptime (s)': serverUptimeS.toStringAsFixed(2),
      'Flutter Build': flutterBuild,
      'Device Uji (Model/OS)': deviceModel,
      'Network (Wi-Fi/4G)': networkType,
    };
  }
}

/// Model untuk Model Info (dari /model_info)
class ModelInfo {
  final String task;
  final String arch;
  final int inChannels;
  final String classes;
  final String modelVersion;
  final String apiVersion;
  final String device;
  final String? checkpointSha256;
  final bool deterministic;

  ModelInfo({
    required this.task,
    required this.arch,
    required this.inChannels,
    required this.classes,
    required this.modelVersion,
    required this.apiVersion,
    required this.device,
    this.checkpointSha256,
    required this.deterministic,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      task: json['task'] ?? 'N/A',
      arch: json['arch'] ?? 'N/A',
      inChannels: json['in_channels'] ?? 0,
      classes: json['classes'] ?? 'N/A',
      modelVersion: json['model_version'] ?? 'N/A',
      apiVersion: json['api_version'] ?? 'N/A',
      device: json['device'] ?? 'N/A',
      checkpointSha256: json['checkpoint_sha256'],
      deterministic: json['deterministic'] ?? false,
    );
  }
}

/// Model untuk Metrics Basic (dari /metrics_basic)
class MetricsBasic {
  final int countRequests;
  final double avgPreMs;
  final double avgInferMs;
  final double avgPostMs;
  final double avgTotalMs;
  final double p95TotalMs;

  MetricsBasic({
    required this.countRequests,
    required this.avgPreMs,
    required this.avgInferMs,
    required this.avgPostMs,
    required this.avgTotalMs,
    required this.p95TotalMs,
  });

  factory MetricsBasic.fromJson(Map<String, dynamic> json) {
    return MetricsBasic(
      countRequests: json['count_requests'] ?? 0,
      avgPreMs: (json['avg_pre_ms'] ?? 0).toDouble(),
      avgInferMs: (json['avg_infer_ms'] ?? 0).toDouble(),
      avgPostMs: (json['avg_post_ms'] ?? 0).toDouble(),
      avgTotalMs: (json['avg_total_ms'] ?? 0).toDouble(),
      p95TotalMs: (json['p95_total_ms'] ?? 0).toDouble(),
    );
  }
}
