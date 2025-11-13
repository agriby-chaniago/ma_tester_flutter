class TestResult {
  final DateTime timestamp;
  final int? clientTotalMs;
  final int? serverInferMs;
  final double? threshold;
  final bool success;

  // Statistics dari API response
  final int? numMicroaneurysms;
  final int? totalAreaPixels;
  final double? coveragePercentage;
  final int? largestComponent;
  final double? meanComponentSize;

  // Per-image metrics (optional, only if ground truth available)
  final double? diceScore;
  final double? iouScore;
  final double? precision;
  final double? recall;
  final double? f1Score;
  final double? accuracy;
  final double? specificity;
  final double? sensitivity;

  TestResult({
    required this.timestamp,
    this.clientTotalMs,
    this.serverInferMs,
    this.threshold,
    this.success = true,
    this.numMicroaneurysms,
    this.totalAreaPixels,
    this.coveragePercentage,
    this.largestComponent,
    this.meanComponentSize,
    this.diceScore,
    this.iouScore,
    this.precision,
    this.recall,
    this.f1Score,
    this.accuracy,
    this.specificity,
    this.sensitivity,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'clientTotalMs': clientTotalMs,
        'serverInferMs': serverInferMs,
        'threshold': threshold,
        'success': success,
        'numMicroaneurysms': numMicroaneurysms,
        'totalAreaPixels': totalAreaPixels,
        'coveragePercentage': coveragePercentage,
        'largestComponent': largestComponent,
        'meanComponentSize': meanComponentSize,
        'diceScore': diceScore,
        'iouScore': iouScore,
        'precision': precision,
        'recall': recall,
        'f1Score': f1Score,
        'accuracy': accuracy,
        'specificity': specificity,
        'sensitivity': sensitivity,
      };

  factory TestResult.fromJson(Map<String, dynamic> json) => TestResult(
        timestamp: DateTime.parse(json['timestamp']),
        clientTotalMs: json['clientTotalMs'],
        serverInferMs: json['serverInferMs'],
        threshold: json['threshold'],
        success: json['success'] ?? true,
        numMicroaneurysms: json['numMicroaneurysms'],
        totalAreaPixels: json['totalAreaPixels'],
        coveragePercentage: json['coveragePercentage'],
        largestComponent: json['largestComponent'],
        meanComponentSize: json['meanComponentSize'],
        diceScore: json['diceScore'],
        iouScore: json['iouScore'],
        precision: json['precision'],
        recall: json['recall'],
        f1Score: json['f1Score'],
        accuracy: json['accuracy'],
        specificity: json['specificity'],
        sensitivity: json['sensitivity'],
      );
}
