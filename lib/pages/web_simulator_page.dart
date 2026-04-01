import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import '../services/api_client.dart';

class WebSimulatorPage extends StatefulWidget {
  const WebSimulatorPage({super.key});

  @override
  State<WebSimulatorPage> createState() => _WebSimulatorPageState();
}

class _WebSimulatorPageState extends State<WebSimulatorPage> {
  static const double _fixedOverlayOpacity = 0.78;
  static const List<String> _simStages = [
    'Load Image',
    'Upload',
    'Inference',
    'Render',
  ];

  late final TextEditingController _baseUrlCtrl;
  final ImagePicker _imagePicker = ImagePicker();

  Uint8List? _inputBytes;
  Uint8List? _maskBytes;
  Uint8List? _overlayBytes;
  String? _fileName;
  String? _mimeType;

  bool _busy = false;
  bool _healthChecking = false;
  bool? _serverReady;
  String _healthMessage = 'Not checked';

  final String _selectedFormat = 'json';
  static const String _inferenceMode = 'real';
  static const bool _allowFallback = false;
  String _viewMode = 'overlay';
  double _threshold = 0.75;

  int? _serverPreMs;
  int? _serverInferMs;
  int? _serverPostMs;
  String? _modeUsed;
  String? _modeFallback;
  bool? _realModeEnabled;
  bool? _realModeReady;
  String? _realModeError;
  Map<String, dynamic>? _statistics;
  String? _lastError;

  final TransformationController _viewerCtrl = TransformationController();
  Timer? _simTicker;
  double _simVisualProgress = 0.0;
  int _simStageIndex = 0;
  String _simStatusText = 'Idle';
  double _compareSplitRatio = 0.5;
  bool _showOutputPulse = false;
  int _outputPulseCycle = 0;

  @override
  void initState() {
    super.initState();
    _baseUrlCtrl = TextEditingController(text: dotenv.env['API_BASE'] ?? '');
  }

  @override
  void dispose() {
    _simTicker?.cancel();
    _baseUrlCtrl.dispose();
    _viewerCtrl.dispose();
    super.dispose();
  }

  String _friendlyNetworkError(Object error, String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return 'Invalid API URL. Use a full URL, for example: http://127.0.0.1:8000 or https://your-domain.com';
    }

    if (kIsWeb && Uri.base.scheme == 'https' && uri.scheme == 'http') {
      return 'Blocked by browser (mixed content): an HTTPS page cannot call an HTTP API. Use an HTTPS API endpoint or run the app locally over HTTP.';
    }

    final host = uri.host;
    final isIpv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(host);
    final likelyIncompleteHost =
        host != 'localhost' && !isIpv4 && !host.contains('.');

    if (likelyIncompleteHost) {
      return 'API hostname looks incomplete: "$host". Please recheck your endpoint URL.';
    }

    if (error is DioException) {
      if (error.type == DioExceptionType.badCertificate) {
        return 'The API HTTPS certificate is invalid. Try an endpoint with a valid certificate or use local HTTP.';
      }

      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.connectionError) {
        return 'Cannot connect to API. Check that backend is running, the URL is correct, and cross-origin access is allowed (CORS/proxy) when using another domain.';
      }
    }

    return error.toString();
  }

  Future<void> _checkHealth() async {
    final baseUrl = _baseUrlCtrl.text.trim();
    if (baseUrl.isEmpty) {
      setState(() {
        _serverReady = false;
        _healthMessage = 'API URL is empty';
      });
      return;
    }

    setState(() {
      _healthChecking = true;
      _lastError = null;
    });

    try {
      final api = ApiClient(baseUrl, timeoutMs: 12000);
      final health = await api.healthz();
      final info = await api.modelInfo();
      final ready = health['ready'] == true;
      final realEnabled = info['real_mode_enabled'] == true;
      final realReady = info['real_mode_ready'] == true;
      final realError = info['real_pipeline_error']?.toString();

      setState(() {
        _serverReady = ready;
        _realModeEnabled = realEnabled;
        _realModeReady = realReady;
        _realModeError = realError;
        _healthMessage = ready ? 'Connected' : 'Server reachable but not ready';
      });
    } catch (e) {
      setState(() {
        _serverReady = false;
        _realModeEnabled = null;
        _realModeReady = null;
        _realModeError = null;
        _healthMessage = 'Connection failed';
        _lastError = _friendlyNetworkError(e, baseUrl);
      });
    } finally {
      setState(() {
        _healthChecking = false;
      });
    }
  }

  String? _runBlockReason() {
    if (_realModeReady != true) {
      return 'Real mode is not ready yet. Please make sure the real backend is ready.';
    }
    return null;
  }

  void _startSimulationVisuals() {
    _simTicker?.cancel();
    setState(() {
      _simVisualProgress = 0.06;
      _simStageIndex = 0;
      _simStatusText = 'Preparing retina image';
    });

    _simTicker = Timer.periodic(const Duration(milliseconds: 260), (timer) {
      if (!mounted || !_busy) {
        timer.cancel();
        return;
      }

      setState(() {
        _simVisualProgress = (_simVisualProgress + 0.035).clamp(0.06, 0.9);
        if (_simVisualProgress >= 0.2) {
          _simStageIndex = 1;
          _simStatusText = 'Uploading image to backend';
        }
        if (_simVisualProgress >= 0.5) {
          _simStageIndex = 2;
          _simStatusText = 'Model is running segmentation';
        }
        if (_simVisualProgress >= 0.8) {
          _simStageIndex = 3;
          _simStatusText = 'Compositing mask and overlay';
        }
      });
    });
  }

  void _markSimulationDone({String? statusText}) {
    _simTicker?.cancel();
    if (!mounted) {
      return;
    }

    setState(() {
      _simVisualProgress = 1.0;
      _simStageIndex = _simStages.length - 1;
      _simStatusText = statusText ?? 'Simulation complete';
    });
  }

  void _markSimulationFailed() {
    _simTicker?.cancel();
    if (!mounted) {
      return;
    }

    setState(() {
      _simVisualProgress = 0.0;
      _simStatusText = 'Simulation failed';
    });
  }

  Future<void> _pickImage() async {
    try {
      final XFile? picked =
          await _imagePicker.pickImage(source: ImageSource.gallery);

      if (picked == null) {
        // User cancelled picker dialog.
        return;
      }

      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) {
        setState(() {
          _lastError = 'Selected file has no readable bytes.';
        });
        return;
      }

      final sizeMb = bytes.length / (1024 * 1024);
      if (sizeMb > 20.0) {
        setState(() {
          _lastError =
              'File is ${sizeMb.toStringAsFixed(2)} MB. Maximum allowed is 20 MB.';
        });
        return;
      }

      final fileName = picked.name.isNotEmpty ? picked.name : 'upload.jpg';

      setState(() {
        _inputBytes = bytes;
        _fileName = fileName;
        _mimeType = lookupMimeType(fileName, headerBytes: bytes);
        _maskBytes = null;
        _overlayBytes = null;
        _statistics = null;
        _serverPreMs = null;
        _serverInferMs = null;
        _serverPostMs = null;
        _modeUsed = null;
        _modeFallback = null;
        _lastError = null;
        _simStageIndex = 0;
        _simVisualProgress = 0.0;
        _simStatusText = 'Image loaded. Ready to run simulation';
        _compareSplitRatio = 0.5;
        _showOutputPulse = false;
      });
    } catch (e) {
      setState(() {
        _lastError = 'Failed to open file picker: $e';
      });
    }
  }

  Future<void> _runSimulation() async {
    if (_inputBytes == null || _fileName == null) {
      setState(() {
        _lastError = 'Please upload an image first.';
      });
      return;
    }

    final baseUrl = _baseUrlCtrl.text.trim();
    if (baseUrl.isEmpty) {
      setState(() {
        _lastError = 'API URL is empty.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _lastError = null;
    });
    _startSimulationVisuals();

    try {
      final api = ApiClient(
        baseUrl,
        timeoutMs: int.tryParse(dotenv.env['TIMEOUT_MS'] ?? '') ?? 90000,
      );

      final response = await api.predictMultipartBytes(
        _inputBytes!,
        filename: _fileName!,
        mimeType: _mimeType,
        timeoutMs: int.tryParse(dotenv.env['TIMEOUT_MS'] ?? '') ?? 90000,
        threshold: _threshold,
        fmt: _selectedFormat,
        returnOverlay: true,
        proba: false,
        mode: _inferenceMode,
        allowFallback: _allowFallback,
      );

      final stats = response['statistics'] as Map<String, dynamic>?;

      setState(() {
        _maskBytes = response['mask'] as Uint8List?;
        _overlayBytes = response['overlay'] as Uint8List?;
        _statistics = stats;
        _serverPreMs = response['serverPreMs'] as int?;
        _serverInferMs = response['serverInferMs'] as int?;
        _serverPostMs = response['serverPostMs'] as int?;
        _modeUsed = response['modeUsed'] as String?;
        _modeFallback = response['modeFallback'] as String?;
        _serverReady = true;
        _healthMessage = 'Connected';
        _viewMode = 'compare';
        _outputPulseCycle += 1;
        _showOutputPulse = true;
      });

      _markSimulationDone(
        statusText: _serverInferMs != null
            ? 'Simulation complete • infer $_serverInferMs ms'
            : 'Simulation complete',
      );
    } catch (e) {
      setState(() {
        _lastError = _friendlyNetworkError(e, baseUrl);
      });
      _markSimulationFailed();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Widget _buildProcessedStageImage() {
    if (_overlayBytes != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(_inputBytes!, fit: BoxFit.contain),
          Opacity(
            opacity: _fixedOverlayOpacity,
            child: Image.memory(_overlayBytes!, fit: BoxFit.contain),
          ),
        ],
      );
    }

    if (_maskBytes != null) {
      return Image.memory(_maskBytes!, fit: BoxFit.contain);
    }

    return Image.memory(_inputBytes!, fit: BoxFit.contain);
  }

  Widget _compareLabel(String text, Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildCompareStage() {
    final processed = _buildProcessedStageImage();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final splitX = width * _compareSplitRatio;
        final handleLeft = (splitX - 21).clamp(0.0, width - 42.0);

        return Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: processed,
            ),
            ClipRect(
              clipper: _SplitClipper(splitX),
              child: Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: Image.memory(_inputBytes!, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              left: splitX - 1,
              top: 0,
              bottom: 0,
              child: Container(
                width: 2,
                color: Colors.white.withValues(alpha: 0.88),
              ),
            ),
            Positioned(
              left: handleLeft,
              top: (constraints.maxHeight / 2) - 21,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF0C3D44),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF90F3E7), width: 1),
                ),
                child: const Icon(
                  Icons.compare_arrows,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            _compareLabel('Before', Alignment.topLeft),
            _compareLabel('After', Alignment.topRight),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  final ratio =
                      (details.localPosition.dx / constraints.maxWidth)
                          .clamp(0.05, 0.95);
                  setState(() {
                    _compareSplitRatio = ratio;
                  });
                },
                onTapDown: (details) {
                  final ratio =
                      (details.localPosition.dx / constraints.maxWidth)
                          .clamp(0.05, 0.95);
                  setState(() {
                    _compareSplitRatio = ratio;
                  });
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCoverageLegend() {
    final coverage = (_statistics?['coverage_percentage'] as num?)?.toDouble();
    final ma = _statistics?['num_microaneurysms'];
    final normalized = ((coverage ?? 0.0) / 100.0).clamp(0.0, 1.0);

    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF041E22).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF5CE4D5).withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Output Insight',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.bubble_chart,
                  size: 14, color: Color(0xFF96FFF3)),
              const SizedBox(width: 6),
              Text(
                'MA: ${ma ?? '-'}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const Spacer(),
              Text(
                '${coverage?.toStringAsFixed(4) ?? '-'}%',
                style: const TextStyle(
                  color: Color(0xFFB7FFF8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final indicatorLeft =
                  (constraints.maxWidth - 3) * normalized.toDouble();
              return Stack(
                children: [
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF1BC9B8),
                          Color(0xFFE9D95A),
                          Color(0xFFE96554),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: indicatorLeft,
                    top: -2,
                    child: Container(
                      width: 3,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            _serverInferMs == null
                ? 'Inference time pending'
                : 'Inference: $_serverInferMs ms',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Map<String, int> _stageTimingMap() {
    final result = <String, int>{};
    if (_serverPreMs != null && _serverPreMs! >= 0) {
      result['Preprocess'] = _serverPreMs!;
    }
    if (_serverInferMs != null && _serverInferMs! >= 0) {
      result['Infer'] = _serverInferMs!;
    }
    if (_serverPostMs != null && _serverPostMs! >= 0) {
      result['Postprocess'] = _serverPostMs!;
    }
    return result;
  }

  Widget _buildStageTimingBreakdown() {
    final timings = _stageTimingMap();
    if (timings.isEmpty) {
      return Text(
        _busy
            ? 'Collecting stage timings from backend...'
            : 'Run simulation to see real stage timings.',
        style: const TextStyle(fontSize: 12, color: Color(0xFF38525B)),
      );
    }

    final total = timings.values.fold<int>(0, (sum, value) => sum + value);
    const colors = <Color>[
      Color(0xFF3AB9A8),
      Color(0xFF0A7C73),
      Color(0xFF0F5E58),
    ];

    int idx = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...timings.entries.map((entry) {
          final color = colors[idx % colors.length];
          idx += 1;
          final ratio = total > 0 ? (entry.value / total).clamp(0.0, 1.0) : 0.0;
          final pct = total > 0 ? (entry.value * 100 / total) : 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '${entry.value} ms • ${pct.toStringAsFixed(1)}%',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF2D4A53)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: ratio,
                    backgroundColor: const Color(0xFFD7E8E5),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ],
            ),
          );
        }),
        if (total > 0)
          Text(
            'Total server stages: $total ms',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF254049),
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  Widget _buildExplainResultCard() {
    if (_busy) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Explain Result\nAnalyzing image and preparing interpretation...',
            style: TextStyle(fontSize: 12, color: Color(0xFF2D4A53)),
          ),
        ),
      );
    }

    if (_statistics == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Explain Result\nRun a simulation to generate an interpretation summary.',
            style: TextStyle(fontSize: 12, color: Color(0xFF2D4A53)),
          ),
        ),
      );
    }

    final ma = (_statistics?['num_microaneurysms'] as num?)?.toInt() ?? 0;
    final coverage =
        (_statistics?['coverage_percentage'] as num?)?.toDouble() ?? 0.0;
    final coverageText = coverage.toStringAsFixed(4);

    String activityLevel;
    String interpretation;
    if (ma == 0 && coverage < 0.01) {
      activityLevel = 'Segmentation activity: very low';
      interpretation = 'Detected components: $ma, coverage: $coverageText%. '
          'No prominent candidate regions were detected at the current threshold.';
    } else if (ma <= 3 && coverage < 0.15) {
      activityLevel = 'Segmentation activity: low';
      interpretation = 'Detected components: $ma, coverage: $coverageText%. '
          'A small number of candidate regions are present with limited spread.';
    } else if (ma <= 8 && coverage < 0.5) {
      activityLevel = 'Segmentation activity: medium';
      interpretation = 'Detected components: $ma, coverage: $coverageText%. '
          'Candidate regions are visible with moderate spread in the segmentation map.';
    } else {
      activityLevel = 'Segmentation activity: high';
      interpretation = 'Detected components: $ma, coverage: $coverageText%. '
          'Many candidate regions or broad coverage were detected in this run.';
    }

    final modeNote = _modeFallback != null
        ? 'Inference used fallback path: $_modeFallback.'
        : 'Inference mode used: ${_modeUsed ?? '-'}.';

    return Card(
      color: const Color(0xFFF4FBF9),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Explain Result',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              activityLevel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF154F47),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              interpretation,
              style: const TextStyle(fontSize: 12, color: Color(0xFF2D4A53)),
            ),
            const SizedBox(height: 6),
            Text(
              modeNote,
              style: const TextStyle(fontSize: 12, color: Color(0xFF2D4A53)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Note: This simulator output is for technical demonstration and triage support only, not a clinical diagnosis.',
              style: TextStyle(fontSize: 11, color: Color(0xFF516C74)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPipelineNode(int index) {
    final isDone = index < _simStageIndex;
    final isActive = index == _simStageIndex;
    final color = isDone || isActive
        ? const Color(0xFF2EC4B6)
        : Colors.white.withValues(alpha: 0.62);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: isActive ? 34 : 30,
          height: isActive ? 34 : 30,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: isActive
                ? const [
                    BoxShadow(
                      color: Color(0x5533D9C8),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            isDone ? Icons.check : Icons.circle,
            size: isDone ? 18 : 8,
            color: isDone ? const Color(0xFF08312E) : Colors.white,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _simStages[index],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.96),
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildSimulationCanvas(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF061A1E), Color(0xFF0A2B30), Color(0xFF12363A)],
        ),
        border: Border.all(color: const Color(0x3345E2D0)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Simulation Theater',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                Chip(
                  backgroundColor: const Color(0xFF06353B),
                  side: const BorderSide(color: Color(0xFF73F0E2)),
                  avatar: Icon(
                    _busy ? Icons.settings_input_component : Icons.bolt,
                    size: 14,
                    color: const Color(0xFFE6FFFB),
                  ),
                  label: Text(
                    _simStatusText,
                    style: const TextStyle(
                      color: Color(0xFFF2FFFD),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(
              children: [
                for (int i = 0; i < _simStages.length; i++) ...[
                  Expanded(child: _buildPipelineNode(i)),
                  if (i != _simStages.length - 1)
                    Container(
                      width: 16,
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 18),
                      color: i < _simStageIndex
                          ? const Color(0xFF2EC4B6)
                          : Colors.white.withValues(alpha: 0.45),
                    ),
                ],
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildImageStage(),
                    if (_showOutputPulse)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: TweenAnimationBuilder<double>(
                            key: ValueKey(_outputPulseCycle),
                            duration: const Duration(milliseconds: 780),
                            tween: Tween(begin: 1.0, end: 0.0),
                            onEnd: () {
                              if (!mounted) {
                                return;
                              }
                              setState(() {
                                _showOutputPulse = false;
                              });
                            },
                            builder: (context, value, _) {
                              return Container(
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    center: Alignment.center,
                                    radius: 1.15,
                                    colors: [
                                      const Color(0xAA8BFFF1)
                                          .withValues(alpha: 0.42 * value),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    if (_statistics != null)
                      Positioned(
                        right: 14,
                        bottom: 14,
                        child: _buildCoverageLegend(),
                      ),
                    if (_busy)
                      Container(
                        color: Colors.black.withValues(alpha: 0.58),
                        alignment: Alignment.center,
                        child: Container(
                          width: 360,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF072429).withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF2EC4B6)
                                  .withValues(alpha: 0.45),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF66E9D8),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Model is processing this image',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  minHeight: 8,
                                  value: _simVisualProgress,
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.14),
                                  valueColor: const AlwaysStoppedAnimation(
                                    Color(0xFF2EC4B6),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _simStatusText,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.96),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageStage() {
    if (_inputBytes == null) {
      return _buildPlaceholder('Upload an image to start simulation');
    }

    if (_viewMode == 'mask' && _maskBytes == null) {
      return _buildPlaceholder('Run simulation to display mask output');
    }

    if (_viewMode == 'overlay' &&
        (_overlayBytes == null && _maskBytes == null)) {
      return _buildPlaceholder('Run simulation to display overlay output');
    }

    Widget content;
    if (_viewMode == 'original') {
      content = Image.memory(_inputBytes!, fit: BoxFit.contain);
    } else if (_viewMode == 'mask') {
      content = Image.memory(_maskBytes!, fit: BoxFit.contain);
    } else if (_viewMode == 'overlay') {
      content = _buildProcessedStageImage();
    } else {
      return _buildCompareStage();
    }

    return InteractiveViewer(
      transformationController: _viewerCtrl,
      minScale: 0.5,
      maxScale: 8,
      child: Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: content,
      ),
    );
  }

  Widget _buildPlaceholder(String text) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE8F6F3), Color(0xFFDDECEF)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, color: Color(0xFF243640)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _serverReady == null
        ? Colors.grey
        : (_serverReady! ? Colors.green : Colors.red);

    return Scaffold(
      backgroundColor: const Color(0xFFEEF3F2),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFE7EFED),
        title: const Text('MA Retinal Simulator'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Chip(
              avatar: Icon(Icons.circle, size: 10, color: statusColor),
              label: Text(_healthMessage),
            ),
          ),
          IconButton(
            onPressed: _healthChecking ? null : _checkHealth,
            icon: _healthChecking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.health_and_safety_outlined),
            tooltip: 'Check API health',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 1200;
          if (!desktop) {
            return _buildMobileFallback(colorScheme);
          }

          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF3F7F6), Color(0xFFE6F0EE)],
              ),
            ),
            child: Row(
              children: [
                SizedBox(width: 336, child: _buildControlPanel(colorScheme)),
                Expanded(child: _buildSimulationCanvas(colorScheme)),
                SizedBox(width: 356, child: _buildResultPanel(colorScheme)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileFallback(ColorScheme colorScheme) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF3F7F6), Color(0xFFE6F0EE)],
        ),
      ),
      child: Column(
        children: [
          Expanded(flex: 6, child: _buildControlPanel(colorScheme)),
          Expanded(flex: 7, child: _buildSimulationCanvas(colorScheme)),
          Expanded(flex: 6, child: _buildResultPanel(colorScheme)),
        ],
      ),
    );
  }

  Widget _buildControlPanel(ColorScheme colorScheme) {
    final runBlockedReason = _runBlockReason();
    final readyText = _realModeReady == true ? 'READY' : 'NOT READY';
    final readyColor = _realModeReady == true
        ? const Color(0xFF0E6E5C)
        : const Color(0xFF955D06);

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.surface.withValues(alpha: 0.95),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0A6861), Color(0xFF1E857D)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.tune, color: Colors.white),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Simulation Controls',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Live',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrlCtrl,
            decoration: const InputDecoration(
              labelText: 'API URL',
              border: OutlineInputBorder(),
            ),
          ),
          if (_realModeEnabled != null || _realModeReady != null) ...[
            const SizedBox(height: 6),
            Text(
              'Real mode backend: $readyText',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: readyColor,
              ),
            ),
          ],
          if (_realModeReady != true &&
              _realModeError != null &&
              _realModeError!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Reason: $_realModeError',
                style: const TextStyle(fontSize: 11, color: Color(0xFF2E3E46)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickImage,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(_fileName == null ? 'Upload Retina Image' : _fileName!),
          ),
          const SizedBox(height: 10),
          Text('Threshold: ${_threshold.toStringAsFixed(2)}'),
          Slider(
            value: _threshold,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            onChanged: _busy
                ? null
                : (v) {
                    setState(() => _threshold = v);
                  },
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_busy || runBlockedReason != null)
                      ? null
                      : _runSimulation,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_busy ? 'Processing...' : 'Run Simulation'),
                ),
              ),
            ],
          ),
          if (runBlockedReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                runBlockedReason,
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A4B00)),
              ),
            ),
          if (_lastError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Text(
                _lastError!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultPanel(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.surface.withValues(alpha: 0.95),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Result Details',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          Card(
            color: const Color(0xFFE7F7F4),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Simulation Pulse',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _simStatusText,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 7,
                      value: _busy
                          ? _simVisualProgress
                          : (_modeUsed != null ? 1.0 : 0.0),
                      backgroundColor: const Color(0xFFD3E8E4),
                      valueColor: const AlwaysStoppedAnimation(
                        Color(0xFF0A7C73),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildStageTimingBreakdown(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildExplainResultCard(),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Key statistics',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _statRow('Microaneurysms',
                      '${_statistics?['num_microaneurysms'] ?? '-'}'),
                  _statRow('Coverage',
                      '${(_statistics?['coverage_percentage'] as num?)?.toStringAsFixed(4) ?? '-'}%'),
                ],
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _statRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(key, style: const TextStyle(fontSize: 12)),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}

class _SplitClipper extends CustomClipper<Rect> {
  final double splitX;

  _SplitClipper(this.splitX);

  @override
  Rect getClip(Size size) {
    final x = splitX.clamp(0.0, size.width);
    return Rect.fromLTWH(0, 0, x, size.height);
  }

  @override
  bool shouldReclip(covariant _SplitClipper oldClipper) {
    return oldClipper.splitX != splitX;
  }
}
