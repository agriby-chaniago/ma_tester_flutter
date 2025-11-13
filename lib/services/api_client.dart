import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';

class ApiClient {
  final Dio _dio;

  ApiClient(String baseUrl, {int timeoutMs = 20000})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl.endsWith('/')
              ? baseUrl.substring(0, baseUrl.length - 1)
              : baseUrl,
          connectTimeout: Duration(milliseconds: timeoutMs),
          receiveTimeout: Duration(milliseconds: timeoutMs),
          sendTimeout: Duration(milliseconds: timeoutMs),
          // Accept all status codes to handle 500 errors gracefully
          validateStatus: (code) => code != null,
        )) {
    // Add logging interceptor for debugging
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: false,
        error: true,
        logPrint: (obj) => debugPrint(obj.toString()),
      ));
    }
  }

  /// Helper to extract error message from response
  static String extractErrorMessage(Response? response) {
    if (response == null) return 'No response from server';

    try {
      // Try to parse as JSON
      Map<String, dynamic>? errorData;

      if (response.data is Map) {
        errorData = response.data as Map<String, dynamic>;
      } else if (response.data is String) {
        try {
          errorData = jsonDecode(response.data as String);
        } catch (_) {
          // Not JSON, return as string
          final dataStr = response.data.toString();
          return dataStr.length > 200
              ? '${dataStr.substring(0, 200)}...'
              : dataStr;
        }
      } else if (response.data is Uint8List) {
        try {
          final text = utf8.decode(response.data as Uint8List);
          errorData = jsonDecode(text);
        } catch (_) {
          return 'Binary response (${(response.data as Uint8List).length} bytes)';
        }
      }

      // Extract error message from common fields
      if (errorData != null) {
        if (errorData['detail'] != null) {
          return errorData['detail'].toString();
        } else if (errorData['error'] != null) {
          return errorData['error'].toString();
        } else if (errorData['message'] != null) {
          return errorData['message'].toString();
        } else {
          return errorData.toString();
        }
      }

      return 'Unknown error (status ${response.statusCode})';
    } catch (e) {
      return 'Error parsing response: $e';
    }
  }

  /// Helper to create detailed exception with server error
  static Exception createDetailedException(
      String operation, Response? response) {
    if (response == null) {
      return Exception('$operation failed: No response from server');
    }

    final statusCode = response.statusCode ?? 0;
    final errorMsg = extractErrorMessage(response);

    return Exception('$operation failed (HTTP $statusCode): $errorMsg');
  }

  Future<Map<String, dynamic>> healthz() async {
    final resp = await _dio.get('/healthz');
    if (resp.statusCode == 200 && resp.data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(resp.data);
    }
    throw createDetailedException('Health check', resp);
  }

  /// GET /model_info - Informasi arsitektur model
  Future<Map<String, dynamic>> modelInfo() async {
    final resp = await _dio.get('/model_info');
    if (resp.statusCode == 200 && resp.data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(resp.data);
    }
    throw createDetailedException('Model info', resp);
  }

  /// GET /metrics_basic - Rolling statistics (last 256 requests)
  ///
  /// Returns:
  /// ```dart
  /// {
  ///   "count_requests": 42,
  ///   "avg_pre_ms": 75.5,
  ///   "avg_infer_ms": 2150.3,
  ///   "avg_post_ms": 28.7,
  ///   "avg_total_ms": 2254.5,
  ///   "p95_total_ms": 2890.2
  /// }
  /// ```
  Future<Map<String, dynamic>> metricsBasic() async {
    final resp = await _dio.get('/metrics_basic');
    if (resp.statusCode == 200 && resp.data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(resp.data);
    }
    throw createDetailedException('Metrics basic', resp);
  }

  /// POST /predict - MA Segmentation dengan multiple output formats
  ///
  /// **Format output (parameter `fmt`):**
  /// - `'png'`: Binary mask PNG (paling ringan, ~5-10KB)
  /// - `'proba'`: Probability map PNG 0-255 (soft mask)
  /// - `'compact'`: JSON minimal (mask_png_b64 + timing)
  /// - `'json'`: JSON lengkap dengan statistics + overlay optional
  ///
  /// **Return Map:**
  /// ```dart
  /// {
  ///   "mask": Uint8List?,           // binary mask atau probability map
  ///   "overlay": Uint8List?,         // red overlay pada original (hanya fmt=json)
  ///   "original": Uint8List?,        // original image (hanya fmt=json)
  ///   "json": Map?,                  // full JSON response
  ///   "statistics": Map?,            // detection statistics (hanya fmt=json)
  ///   "status": int,                 // HTTP status code
  ///   "latencyMs": int?,             // inference latency dari server
  ///   "clientTotalMs": int?,         // total round-trip time
  ///   "serverInferMs": int?,         // server inference time only
  ///   "requestId": String?,          // x-request-id untuk tracing
  ///   "outputType": String?,         // 'mask' atau 'probability_u8'
  ///   "probaNpyB64": String?,        // lossless probability (hanya jika proba=true)
  /// }
  /// ```
  Future<Map<String, dynamic>> predictMultipart(
    String filePath, {
    Map<String, dynamic>? extraFields,
    int? timeoutMs,
    double?
        threshold, // threshold untuk binarisasi (0.0-1.0), tidak berlaku untuk fmt=proba
    String fmt = 'json', // png | proba | compact | json
    bool returnOverlay = true, // request overlay image (hanya untuk fmt=json)
    bool proba =
        false, // request lossless probability map (hanya untuk fmt=json)
  }) async {
    final dio = Dio(BaseOptions(
      baseUrl: _dio.options.baseUrl,
      connectTimeout: _dio.options.connectTimeout,
      receiveTimeout: Duration(milliseconds: timeoutMs ?? 90000),
      sendTimeout: Duration(milliseconds: timeoutMs ?? 90000),
      // Accept all status codes to handle errors properly
      validateStatus: (code) => code != null,
    ));

    // Detect MIME type dari file extension
    final filename = filePath.split('/').last;
    final mimeType = lookupMimeType(filePath) ?? 'image/jpeg';
    final contentType = MediaType.parse(mimeType);

    // Debug log
    if (kDebugMode) {
      print('[ApiClient] Uploading file: $filename');
      print('[ApiClient] Detected MIME type: $mimeType');
      print('[ApiClient] Content-Type: ${contentType.mimeType}');
    }

    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        filename: filename,
        contentType: contentType,
      ),
      if (extraFields != null) ...extraFields,
    });

    final params = <String, dynamic>{
      'fmt': fmt, // png | proba | compact | json
      // threshold tidak berlaku untuk fmt=proba (probability map 0-255)
      if (threshold != null && fmt != 'proba')
        'threshold': threshold.toString(),
      // return_overlay dan proba hanya untuk fmt=json
      if (fmt == 'json') ...{
        'return_overlay': returnOverlay.toString(),
        'proba': proba.toString(),
      },
    };

    final sw = Stopwatch()..start();
    final resp = await dio.post(
      '/predict',
      queryParameters: params,
      data: form,
      options: Options(
        responseType: ResponseType.bytes,
        contentType: 'multipart/form-data',
      ),
    );
    sw.stop();

    // Check for error status codes
    if (resp.statusCode != null &&
        (resp.statusCode! < 200 || resp.statusCode! >= 300)) {
      throw createDetailedException('Predict', resp);
    }

    final responseContentType = resp.headers.value('content-type') ?? '';
    final requestId = resp.headers.value('x-request-id'); // UUID untuk tracing
    Uint8List? maskBytes;
    Uint8List? overlayBytes;
    Uint8List? originalBytes;
    Map<String, dynamic>? js;
    Map<String, dynamic>? statistics;
    String? probaNpyB64; // lossless probability map (.npy base64)

    // Helper untuk parse int dari string
    int? toInt(String? s) {
      if (s == null) return null;
      final v = double.tryParse(s);
      return v?.round();
    }

    // Ambil timing dari header kalau ada
    int? latFromHeaders() {
      final pre = toInt(resp.headers.value('x-pre-ms'));
      final inf = toInt(resp.headers.value('x-infer-ms'));
      final post = toInt(resp.headers.value('x-post-ms'));
      if (inf != null) return inf; // pakai infer_ms sebagai representatif
      return pre ?? post;
    }

    // Ambil server infer ms khusus
    final serverInferMs = toInt(resp.headers.value('x-infer-ms'));

    // helper: data URL → bytes
    Uint8List? fromDataUrl(String? dataUrl) {
      if (dataUrl == null) return null;
      final idx = dataUrl.indexOf(',');
      if (idx < 0) return null;
      try {
        return base64Decode(dataUrl.substring(idx + 1));
      } catch (_) {
        return null;
      }
    }

    // --- CASE 1: Response berupa image/png (fmt=png atau fmt=proba) ---
    if (responseContentType.contains('image/png')) {
      final outputType = resp.headers.value('x-output') ??
          'mask'; // 'mask' atau 'probability_u8'
      return {
        'mask': resp.data as Uint8List,
        'overlay': null,
        'original': null,
        'json': null,
        'statistics': null,
        'status': resp.statusCode,
        'latencyMs': latFromHeaders() ?? sw.elapsedMilliseconds,
        'clientTotalMs': sw.elapsedMilliseconds,
        'serverInferMs': serverInferMs,
        'requestId': requestId,
        'outputType':
            outputType, // untuk distinguish antara binary mask vs probability
      };
    }

    // --- CASE 2: Response berupa JSON (fmt=compact atau fmt=json) ---
    try {
      final text = utf8.decode(resp.data as Uint8List);
      js = jsonDecode(text);

      // Parse mask dari berbagai format yang mungkin
      if (js != null && js['mask_png_b64'] != null) {
        // Format compact: mask_png_b64
        maskBytes = base64Decode(js['mask_png_b64']);
      }
      if (js != null && js['segmentation_mask'] != null) {
        // Format json: segmentation_mask (data URL)
        maskBytes ??= fromDataUrl(js['segmentation_mask'] as String?);
      }

      // Parse overlay & original (hanya ada di fmt=json dengan return_overlay=true)
      if (js != null) {
        overlayBytes = fromDataUrl(js['overlay_image'] as String?);
        originalBytes = fromDataUrl(js['original_image'] as String?);
      }

      // Extract statistics (hanya ada di fmt=json)
      if (js != null && js['statistics'] is Map) {
        statistics = Map<String, dynamic>.from(js['statistics']);
      }

      // Extract lossless probability map (hanya ada di fmt=json dengan proba=true)
      if (js != null && js['proba_npy_b64'] is String) {
        probaNpyB64 = js['proba_npy_b64'];
      }

      // Latency dari timing_ms di payload atau fallback ke header/stopwatch
      final timing = (js != null && js['timing_ms'] is Map)
          ? js['timing_ms'] as Map
          : null;
      final latency = timing?['infer_ms'] ??
          timing?['pre_ms'] ??
          timing?['post_ms'] ??
          (js != null ? js['latency_ms'] : null) ??
          latFromHeaders() ??
          sw.elapsedMilliseconds;

      // Server inference time dari timing_ms.infer_ms atau header x-infer-ms
      final serverInferMsFinal = serverInferMs ??
          (timing?['infer_ms'] is num
              ? (timing!['infer_ms'] as num).toInt()
              : null);

      return {
        'mask': maskBytes,
        'overlay': overlayBytes,
        'original': originalBytes,
        'json': js,
        'statistics': statistics,
        'status': resp.statusCode,
        'latencyMs':
            (latency is num) ? latency.toInt() : sw.elapsedMilliseconds,
        'clientTotalMs': sw.elapsedMilliseconds,
        'serverInferMs': serverInferMsFinal,
        'requestId': requestId,
        'probaNpyB64': probaNpyB64, // lossless probability map (base64 .npy)
      };
    } catch (_) {
      throw Exception(
          'Unknown response: status=${resp.statusCode}, contentType=$contentType');
    }
  }

  /// POST /predict_batch - Batch prediction dengan multiple images
  ///
  /// **Format output (parameter `fmt`):**
  /// - `'compact'`: List dengan mask_png_b64 untuk setiap image (default)
  /// - `'stats'`: List dengan statistics (num_components, coverage_pct) tanpa mask
  ///
  /// **Return Map:**
  /// ```dart
  /// {
  ///   "status": "completed",
  ///   "count": 3,
  ///   "results": [
  ///     {
  ///       "filename": "image1.jpg",
  ///       "mask_png_b64": "...",  // hanya untuk fmt=compact
  ///       "num_components": 5,     // hanya untuk fmt=stats
  ///       "coverage_pct": 1.234,   // hanya untuk fmt=stats
  ///       "status": "success",     // or "error"
  ///       "error": "...",          // jika ada error
  ///     },
  ///     ...
  ///   ],
  ///   "requestId": "...",
  /// }
  /// ```
  Future<Map<String, dynamic>> predictBatch(
    List<String> filePaths, {
    int? timeoutMs,
    double? threshold, // threshold untuk binarisasi (0.0-1.0), default 0.75
    String fmt = 'compact', // compact | stats
  }) async {
    if (filePaths.isEmpty) {
      throw Exception('No files provided for batch prediction');
    }

    if (filePaths.length > 10) {
      throw Exception('Maximum 10 images allowed per batch');
    }

    final dio = Dio(BaseOptions(
      baseUrl: _dio.options.baseUrl,
      connectTimeout: _dio.options.connectTimeout,
      receiveTimeout:
          Duration(milliseconds: timeoutMs ?? 120000), // 2 minutes for batch
      sendTimeout: Duration(milliseconds: timeoutMs ?? 120000),
      validateStatus: (code) => code != null,
    ));

    // Build FormData with multiple files
    // FastAPI expects: files: list[UploadFile] = File(...)
    final fileList = <MultipartFile>[];
    for (final path in filePaths) {
      fileList.add(await MultipartFile.fromFile(path));
    }

    final form = FormData.fromMap({
      'files': fileList,
    });

    final params = <String, dynamic>{
      'fmt': fmt, // compact | stats
      if (threshold != null) 'threshold': threshold.toString(),
    };

    final sw = Stopwatch()..start();
    final resp = await dio.post(
      '/predict_batch',
      queryParameters: params,
      data: form,
      options: Options(responseType: ResponseType.json),
    );
    sw.stop();

    // Check for error status codes
    if (resp.statusCode != null &&
        (resp.statusCode! < 200 || resp.statusCode! >= 300)) {
      throw createDetailedException('Predict batch', resp);
    }

    final requestId = resp.headers.value('x-request-id');

    try {
      final data = resp.data as Map<String, dynamic>;

      return {
        'status': data['status'] ?? 'unknown',
        'count': data['count'] ?? 0,
        'results': data['results'] ?? [],
        'requestId': requestId,
        'clientTotalMs': sw.elapsedMilliseconds,
      };
    } catch (e) {
      throw Exception(
          'Failed to parse batch response: $e (status=${resp.statusCode})');
    }
  }
}
