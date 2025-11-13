/// Model untuk menyimpan detail verification per test case
class TestCaseVerification {
  final String step;
  final String action;
  final String expectedResult;
  String? actualResult;
  bool? isVerified;

  TestCaseVerification({
    required this.step,
    required this.action,
    required this.expectedResult,
    this.actualResult,
    this.isVerified,
  });

  Map<String, dynamic> toJson() {
    return {
      'step': step,
      'action': action,
      'expectedResult': expectedResult,
      'actualResult': actualResult,
      'isVerified': isVerified,
    };
  }
}

/// Extended TestCase dengan detail verification
class DetailedTestCase {
  final String caseId;
  final String name;
  final String endpoint;
  final String method;
  final String priority;
  final String category;
  final List<TestCaseVerification> verifications;
  final Map<String, dynamic>? testData;
  final Map<String, dynamic>? expectedResponse;
  String? overallStatus; // PASS/FAIL
  String? notes;

  // Results
  int? actualStatusCode;
  Map<String, dynamic>? actualResults;

  DetailedTestCase({
    required this.caseId,
    required this.name,
    required this.endpoint,
    required this.method,
    required this.priority,
    required this.category,
    required this.verifications,
    this.testData,
    this.expectedResponse,
    this.overallStatus,
    this.notes,
    this.actualStatusCode,
    this.actualResults,
  });

  bool get isPassed => overallStatus == 'PASS';
  bool get isFailed => overallStatus == 'FAIL';
  bool get isPending => overallStatus == null || overallStatus!.isEmpty;
}

/// Template untuk semua test cases
class TestCaseTemplates {
  static DetailedTestCase tc001HealthCheck() {
    return DetailedTestCase(
      caseId: 'TC-001',
      name: 'Health Check - GET /',
      endpoint: '/',
      method: 'GET',
      priority: 'High',
      category: 'Functional',
      verifications: [
        TestCaseVerification(
          step: '1',
          action: 'Send GET request to `/`',
          expectedResult: 'HTTP 200 OK',
        ),
        TestCaseVerification(
          step: '2',
          action: 'Verify `status` field',
          expectedResult: 'Value: "ok"',
        ),
        TestCaseVerification(
          step: '3',
          action: 'Verify `ready` field',
          expectedResult: 'Value: true',
        ),
        TestCaseVerification(
          step: '4',
          action: 'Verify `api_version` field',
          expectedResult: 'Value: "2.0.0"',
        ),
        TestCaseVerification(
          step: '5',
          action: 'Verify `device` field',
          expectedResult: 'Contains device info (e.g., "cuda", "cpu")',
        ),
        TestCaseVerification(
          step: '6',
          action: 'Verify `x-request-id` header',
          expectedResult: 'UUID format present',
        ),
      ],
    );
  }

  static DetailedTestCase tc002ModelInfo() {
    return DetailedTestCase(
      caseId: 'TC-002',
      name: 'Get Model Architecture Info - GET /model_info',
      endpoint: '/model_info',
      method: 'GET',
      priority: 'High',
      category: 'Functional',
      verifications: [
        TestCaseVerification(
          step: '1',
          action: 'Send GET request to `/model_info`',
          expectedResult: 'HTTP 200 OK',
        ),
        TestCaseVerification(
          step: '2',
          action: 'Verify `task` field',
          expectedResult: '"Microaneurysm Segmentation"',
        ),
        TestCaseVerification(
          step: '3',
          action: 'Verify `arch` field',
          expectedResult: '"UNetLinformerMamba"',
        ),
        TestCaseVerification(
          step: '4',
          action: 'Verify `in_channels` field',
          expectedResult: '1',
        ),
        TestCaseVerification(
          step: '5',
          action: 'Verify `classes` field',
          expectedResult: '"Binary"',
        ),
        TestCaseVerification(
          step: '6',
          action: 'Verify `checkpoint_sha256` field',
          expectedResult: 'SHA256 hash present',
        ),
      ],
    );
  }

  static DetailedTestCase tc003MetricsBasic() {
    return DetailedTestCase(
      caseId: 'TC-003',
      name: 'Get Rolling Statistics - GET /metrics_basic',
      endpoint: '/metrics_basic',
      method: 'GET',
      priority: 'Medium',
      category: 'Functional',
      verifications: [
        TestCaseVerification(
          step: '1',
          action: 'Send GET request to `/metrics_basic`',
          expectedResult: 'HTTP 200 OK',
        ),
        TestCaseVerification(
          step: '2',
          action: 'Verify `count_requests` field',
          expectedResult: 'Integer >= 0',
        ),
        TestCaseVerification(
          step: '3',
          action: 'Verify `avg_pre_ms` field',
          expectedResult: 'Float >= 0',
        ),
        TestCaseVerification(
          step: '4',
          action: 'Verify `avg_infer_ms` field',
          expectedResult: 'Float >= 0',
        ),
        TestCaseVerification(
          step: '5',
          action: 'Verify `avg_post_ms` field',
          expectedResult: 'Float >= 0',
        ),
        TestCaseVerification(
          step: '6',
          action: 'Verify `avg_total_ms` field',
          expectedResult: 'Float >= 0',
        ),
        TestCaseVerification(
          step: '7',
          action: 'Verify `p95_total_ms` field',
          expectedResult: 'Float >= 0',
        ),
      ],
    );
  }

  static DetailedTestCase tc004PredictPng() {
    return DetailedTestCase(
      caseId: 'TC-004',
      name: 'Single Prediction - PNG Binary Mask',
      endpoint: '/predict',
      method: 'POST',
      priority: 'High',
      category: 'Functional',
      verifications: [
        TestCaseVerification(
          step: '1',
          action: 'Prepare valid fundus image (JPEG/PNG)',
          expectedResult: 'File < 8MB',
        ),
        TestCaseVerification(
          step: '2',
          action: 'Send POST to `/predict?fmt=png&threshold=0.5`',
          expectedResult: 'HTTP 200 OK',
        ),
        TestCaseVerification(
          step: '3',
          action: 'Verify Content-Type header',
          expectedResult: '"image/png"',
        ),
        TestCaseVerification(
          step: '4',
          action: 'Verify response is PNG binary',
          expectedResult: 'Valid PNG signature',
        ),
        TestCaseVerification(
          step: '5',
          action: 'Verify PNG can be decoded',
          expectedResult: 'Image opens successfully',
        ),
        TestCaseVerification(
          step: '6',
          action: 'Verify `x-request-id` header',
          expectedResult: 'UUID present',
        ),
      ],
    );
  }

  static DetailedTestCase tc005PredictProba() {
    return DetailedTestCase(
      caseId: 'TC-005',
      name: 'Single Prediction - Probability Map PNG',
      endpoint: '/predict',
      method: 'POST',
      priority: 'Medium',
      category: 'Functional',
      verifications: [
        TestCaseVerification(
          step: '1',
          action: 'Prepare valid fundus image',
          expectedResult: 'File < 8MB',
        ),
        TestCaseVerification(
          step: '2',
          action: 'Send POST to `/predict?fmt=proba`',
          expectedResult: 'HTTP 200 OK',
        ),
        TestCaseVerification(
          step: '3',
          action: 'Verify Content-Type header',
          expectedResult: '"image/png"',
        ),
        TestCaseVerification(
          step: '4',
          action: 'Verify PNG is grayscale',
          expectedResult: '0-255 probability values',
        ),
        TestCaseVerification(
          step: '5',
          action: 'Verify `x-output-type` header',
          expectedResult: '"probability_u8"',
        ),
      ],
    );
  }

  static DetailedTestCase tc006PredictCompact() {
    return DetailedTestCase(
      caseId: 'TC-006',
      name: 'Single Prediction - Compact JSON',
      endpoint: '/predict',
      method: 'POST',
      priority: 'Medium',
      category: 'Functional',
      verifications: [
        TestCaseVerification(
          step: '1',
          action: 'Prepare valid fundus image',
          expectedResult: 'File < 8MB',
        ),
        TestCaseVerification(
          step: '2',
          action: 'Send POST to `/predict?fmt=compact&threshold=0.5`',
          expectedResult: 'HTTP 200 OK',
        ),
        TestCaseVerification(
          step: '3',
          action: 'Verify JSON structure',
          expectedResult: 'Contains `mask_png_b64`, `timing_ms`',
        ),
        TestCaseVerification(
          step: '4',
          action: 'Verify mask is base64 encoded PNG',
          expectedResult: 'Decodable PNG data',
        ),
        TestCaseVerification(
          step: '5',
          action: 'Verify timing_ms has valid values',
          expectedResult: 'All values >= 0',
        ),
      ],
    );
  }

  static DetailedTestCase tc007PredictJson() {
    return DetailedTestCase(
      caseId: 'TC-007',
      name: 'Single Prediction - Full JSON Response',
      endpoint: '/predict',
      method: 'POST',
      priority: 'High',
      category: 'Functional',
      verifications: [
        TestCaseVerification(
          step: '1',
          action: 'Prepare valid fundus image',
          expectedResult: 'File < 8MB',
        ),
        TestCaseVerification(
          step: '2',
          action: 'Send POST to `/predict?fmt=json&threshold=0.5`',
          expectedResult: 'HTTP 200 OK',
        ),
        TestCaseVerification(
          step: '3',
          action: 'Verify JSON has all required fields',
          expectedResult: 'status, filename, image_size, threshold, etc.',
        ),
        TestCaseVerification(
          step: '4',
          action: 'Verify statistics accuracy',
          expectedResult: 'All values within valid ranges',
        ),
        TestCaseVerification(
          step: '5',
          action: 'Verify timing_ms present',
          expectedResult: 'All timing values >= 0',
        ),
        TestCaseVerification(
          step: '6',
          action: 'Verify images are base64 encoded',
          expectedResult: 'Decodable PNG data',
        ),
      ],
    );
  }

  static DetailedTestCase tc008BatchCompact() {
    return DetailedTestCase(
      caseId: 'TC-008',
      name: 'Batch Prediction - Compact Format',
      endpoint: '/predict_batch',
      method: 'POST',
      priority: 'High',
      category: 'Functional',
      verifications: [
        TestCaseVerification(
          step: '1',
          action: 'Prepare 3 valid fundus images',
          expectedResult: 'All files < 8MB',
        ),
        TestCaseVerification(
          step: '2',
          action: 'Send POST to `/predict_batch?fmt=compact&threshold=0.5`',
          expectedResult: 'HTTP 200 OK',
        ),
        TestCaseVerification(
          step: '3',
          action: 'Verify JSON structure',
          expectedResult: 'Contains `status`, `count`, `results`',
        ),
        TestCaseVerification(
          step: '4',
          action: 'Verify count matches number of images',
          expectedResult: 'count = 3',
        ),
        TestCaseVerification(
          step: '5',
          action: 'Verify each result has mask_png_b64',
          expectedResult: 'All masks present',
        ),
      ],
    );
  }

  static DetailedTestCase tc009BatchStats() {
    return DetailedTestCase(
      caseId: 'TC-009',
      name: 'Batch Prediction - Statistics Format',
      endpoint: '/predict_batch',
      method: 'POST',
      priority: 'Medium',
      category: 'Functional',
      verifications: [
        TestCaseVerification(
          step: '1',
          action: 'Prepare 3 valid fundus images',
          expectedResult: 'All files < 8MB',
        ),
        TestCaseVerification(
          step: '2',
          action: 'Send POST to `/predict_batch?fmt=stats&threshold=0.5`',
          expectedResult: 'HTTP 200 OK',
        ),
        TestCaseVerification(
          step: '3',
          action: 'Verify each result has statistics',
          expectedResult: 'No mask images, only stats',
        ),
        TestCaseVerification(
          step: '4',
          action: 'Verify statistics are accurate',
          expectedResult: 'Valid ranges for all fields',
        ),
      ],
    );
  }

  static List<DetailedTestCase> getAllTestCases() {
    return [
      tc001HealthCheck(),
      tc002ModelInfo(),
      tc003MetricsBasic(),
      tc004PredictPng(),
      tc005PredictProba(),
      tc006PredictCompact(),
      tc007PredictJson(),
      tc008BatchCompact(),
      tc009BatchStats(),
    ];
  }
}
