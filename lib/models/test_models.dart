/// Model untuk Test Case (Tabel 2: Skenario Testing)
class TestCase {
  final String caseId;
  final String skenario;
  final String endpoint;
  final String method;
  final String? inputMime;
  final int? inputPx;
  final double? inputMB;
  final String? paramFmt;
  final double? paramThreshold;
  final String? paramFlags;
  final String expected;
  final String actual;
  final int statusCode;
  final bool passed;
  final String? catatan;

  TestCase({
    required this.caseId,
    required this.skenario,
    required this.endpoint,
    required this.method,
    this.inputMime,
    this.inputPx,
    this.inputMB,
    this.paramFmt,
    this.paramThreshold,
    this.paramFlags,
    required this.expected,
    required this.actual,
    required this.statusCode,
    required this.passed,
    this.catatan,
  });
}

/// Model untuk Predict Result Detail (Tabel 3: Detail per Request)
class PredictResultDetail {
  final String caseId;
  final String requestId;
  final String filename;
  final int width;
  final int height;
  final double inputKB;
  final double responseKB;
  final String status;
  final double xPreMs;
  final double xInferMs;
  final double xPostMs;
  final double xTotalMs;
  final String? xInputSha256;
  final String? xOutputSha256;
  final String apiVer;
  final String modelVer;
  final String? ckptSha;
  final String? catatan;

  PredictResultDetail({
    required this.caseId,
    required this.requestId,
    required this.filename,
    required this.width,
    required this.height,
    required this.inputKB,
    required this.responseKB,
    required this.status,
    required this.xPreMs,
    required this.xInferMs,
    required this.xPostMs,
    required this.xTotalMs,
    this.xInputSha256,
    this.xOutputSha256,
    required this.apiVer,
    required this.modelVer,
    this.ckptSha,
    this.catatan,
  });

  double get totalMs => xPreMs + xInferMs + xPostMs;

  factory PredictResultDetail.fromResponse({
    required String caseId,
    required String filename,
    required Map<String, dynamic> response,
    required Map<String, String> headers,
    required int width,
    required int height,
    required double inputKB,
    required double responseKB,
  }) {
    final timing = response['timing_ms'] as Map<String, dynamic>?;
    return PredictResultDetail(
      caseId: caseId,
      requestId: headers['x-request-id'] ?? 'N/A',
      filename: filename,
      width: width,
      height: height,
      inputKB: inputKB,
      responseKB: responseKB,
      status: response['status'] ?? 'unknown',
      xPreMs: timing?['pre_ms']?.toDouble() ?? 0.0,
      xInferMs: timing?['infer_ms']?.toDouble() ?? 0.0,
      xPostMs: timing?['post_ms']?.toDouble() ?? 0.0,
      xTotalMs: ((timing?['pre_ms'] ?? 0) +
              (timing?['infer_ms'] ?? 0) +
              (timing?['post_ms'] ?? 0))
          .toDouble(),
      xInputSha256: headers['x-input-sha256'],
      xOutputSha256: headers['x-output-sha256'],
      apiVer: response['api_version'] ?? 'N/A',
      modelVer: response['model_version'] ?? 'N/A',
      ckptSha: response['checkpoint_sha256'],
    );
  }
}

/// Model untuk Statistics (Tabel 5: Statistik Segmentasi)
class SegmentationStatistics {
  final String caseId;
  final int numMicroaneurysms;
  final int totalAreaPixels;
  final double coveragePercentage;
  final int largestComponent;
  final int smallestComponent;
  final double meanComponentSize;
  final List<int> componentAreas;

  SegmentationStatistics({
    required this.caseId,
    required this.numMicroaneurysms,
    required this.totalAreaPixels,
    required this.coveragePercentage,
    required this.largestComponent,
    required this.smallestComponent,
    required this.meanComponentSize,
    required this.componentAreas,
  });

  factory SegmentationStatistics.fromJson(
      String caseId, Map<String, dynamic> json) {
    return SegmentationStatistics(
      caseId: caseId,
      numMicroaneurysms: json['num_microaneurysms'] ?? 0,
      totalAreaPixels: json['total_area_pixels'] ?? 0,
      coveragePercentage: (json['coverage_percentage'] ?? 0.0).toDouble(),
      largestComponent: json['largest_component'] ?? 0,
      smallestComponent: json['smallest_component'] ?? 0,
      meanComponentSize: (json['mean_component_size'] ?? 0.0).toDouble(),
      componentAreas: (json['component_areas'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
    );
  }
}

/// Model untuk Batch Summary (Tabel 6: Ringkasan Batch)
class BatchSummary {
  final String batchId;
  final int totalFiles;
  final int sukses;
  final int error;
  final double avgCoveragePercent;
  final double avgNumComponents;
  final double waktuTotalMs;
  final String? catatan;

  BatchSummary({
    required this.batchId,
    required this.totalFiles,
    required this.sukses,
    required this.error,
    required this.avgCoveragePercent,
    required this.avgNumComponents,
    required this.waktuTotalMs,
    this.catatan,
  });
}

/// Model untuk Batch Item Detail (Tabel 7: Detail Item Batch)
class BatchItemDetail {
  final String batchId;
  final String filename;
  final String status;
  final String? error;
  final int? numComponents;
  final double? coveragePct;
  final String? maskPngB64Prefix;

  BatchItemDetail({
    required this.batchId,
    required this.filename,
    required this.status,
    this.error,
    this.numComponents,
    this.coveragePct,
    this.maskPngB64Prefix,
  });
}

/// Model untuk Latency Percentiles (Tabel 4: Performa)
class LatencyPercentiles {
  final int n;
  final double p50Ms;
  final double p90Ms;
  final double p95Ms;
  final double p99Ms;
  final double avgTotalMs;
  final double avgPre;
  final double avgInfer;
  final double avgPost;
  final double maxRpsSingleThread;
  final double? maxRpsMultiThread;

  LatencyPercentiles({
    required this.n,
    required this.p50Ms,
    required this.p90Ms,
    required this.p95Ms,
    required this.p99Ms,
    required this.avgTotalMs,
    required this.avgPre,
    required this.avgInfer,
    required this.avgPost,
    required this.maxRpsSingleThread,
    this.maxRpsMultiThread,
  });

  factory LatencyPercentiles.calculate(List<PredictResultDetail> results) {
    if (results.isEmpty) {
      return LatencyPercentiles(
        n: 0,
        p50Ms: 0,
        p90Ms: 0,
        p95Ms: 0,
        p99Ms: 0,
        avgTotalMs: 0,
        avgPre: 0,
        avgInfer: 0,
        avgPost: 0,
        maxRpsSingleThread: 0,
      );
    }

    final totalTimes = results.map((r) => r.xTotalMs).toList()..sort();
    final preTimes = results.map((r) => r.xPreMs).toList();
    final inferTimes = results.map((r) => r.xInferMs).toList();
    final postTimes = results.map((r) => r.xPostMs).toList();

    double percentile(List<double> sorted, double p) {
      final index = (p / 100 * (sorted.length - 1)).round();
      return sorted[index];
    }

    final avgTotal = totalTimes.reduce((a, b) => a + b) / totalTimes.length;
    final avgPre = preTimes.reduce((a, b) => a + b) / preTimes.length;
    final avgInfer = inferTimes.reduce((a, b) => a + b) / inferTimes.length;
    final avgPost = postTimes.reduce((a, b) => a + b) / postTimes.length;

    // RPS = 1000 / avg_latency_ms
    final maxRps = avgTotal > 0 ? (1000 / avgTotal).toDouble() : 0.0;

    return LatencyPercentiles(
      n: results.length,
      p50Ms: percentile(totalTimes, 50),
      p90Ms: percentile(totalTimes, 90),
      p95Ms: percentile(totalTimes, 95),
      p99Ms: percentile(totalTimes, 99),
      avgTotalMs: avgTotal,
      avgPre: avgPre,
      avgInfer: avgInfer,
      avgPost: avgPost,
      maxRpsSingleThread: maxRps,
    );
  }
}

/// Model untuk Error Case (Tabel 8: Error Handling)
class ErrorCase {
  final String caseId;
  final String skenario;
  final String input;
  final int expectedCode;
  final int actualCode;
  final String? errorJson;
  final String? detailJson;
  final String? errorCode;
  final bool passed;

  ErrorCase({
    required this.caseId,
    required this.skenario,
    required this.input,
    required this.expectedCode,
    required this.actualCode,
    this.errorJson,
    this.detailJson,
    this.errorCode,
    required this.passed,
  });
}

/// Model untuk Performance Target (Tabel 9: Target vs Hasil)
class PerformanceTarget {
  final String aspek;
  final String target;
  final String hasil;
  final bool lulus;
  final String? catatan;

  PerformanceTarget({
    required this.aspek,
    required this.target,
    required this.hasil,
    required this.lulus,
    this.catatan,
  });
}
