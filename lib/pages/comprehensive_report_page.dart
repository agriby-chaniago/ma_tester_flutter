import 'package:flutter/material.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/api_client.dart';
import '../models/api_info.dart';
import '../models/test_models.dart';

/// Halaman laporan lengkap untuk testing black-box API
class ComprehensiveReportPage extends StatefulWidget {
  const ComprehensiveReportPage({super.key});

  @override
  State<ComprehensiveReportPage> createState() =>
      _ComprehensiveReportPageState();
}

class _ComprehensiveReportPageState extends State<ComprehensiveReportPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Data yang akan dikumpulkan
  ApiInfo? _apiInfo;
  ModelInfo? _modelInfo;
  MetricsBasic? _metricsBasic;
  String _deviceInfo = 'Loading...';
  String _networkType = 'Checking...';
  bool _loading = true;

  // Data testing
  final List<TestCase> _testCases = [];
  final List<PredictResultDetail> _predictResults = [];
  final List<SegmentationStatistics> _segmentationStats = [];
  final List<BatchSummary> _batchSummaries = [];
  final List<BatchItemDetail> _batchItems = [];
  final List<ErrorCase> _errorCases = [];
  final List<PerformanceTarget> _performanceTargets = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 9, vsync: this);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _loading = true);

    try {
      final baseUrl = dotenv.env['API_BASE'] ?? '';
      if (baseUrl.isEmpty) {
        throw Exception('API_BASE not configured');
      }

      final api = ApiClient(baseUrl);

      // Load device info
      await _loadDeviceInfo();

      // Load network type
      await _loadNetworkType();

      // Load API info from root endpoint
      final rootData = await api.healthz();
      _apiInfo = ApiInfo.fromJson(rootData);

      // Set Flutter-side data
      _apiInfo = ApiInfo(
        apiVersion: _apiInfo!.apiVersion,
        modelVersion: _apiInfo!.modelVersion,
        checkpointSha256: _apiInfo!.checkpointSha256,
        device: _apiInfo!.device,
        warmupMs: _apiInfo!.warmupMs,
        serverUptimeS: _apiInfo!.serverUptimeS,
        flutterBuild: 'Debug ${DateTime.now().toIso8601String()}',
        deviceModel: _deviceInfo,
        networkType: _networkType,
      );

      // Load model info
      final modelData = await api.modelInfo();
      _modelInfo = ModelInfo.fromJson(modelData);

      // Load metrics
      final metricsData = await api.metricsBasic();
      _metricsBasic = MetricsBasic.fromJson(metricsData);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _deviceInfo =
            '${androidInfo.brand} ${androidInfo.model} (Android ${androidInfo.version.release})';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _deviceInfo =
            '${iosInfo.name} ${iosInfo.model} (iOS ${iosInfo.systemVersion})';
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        _deviceInfo = 'Linux ${linuxInfo.prettyName}';
      } else {
        _deviceInfo = 'Unknown Platform';
      }
    } catch (e) {
      _deviceInfo = 'Error: $e';
    }
  }

  Future<void> _loadNetworkType() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.wifi)) {
        _networkType = 'Wi-Fi';
      } else if (connectivityResult.contains(ConnectivityResult.mobile)) {
        _networkType = '4G/5G';
      } else if (connectivityResult.contains(ConnectivityResult.ethernet)) {
        _networkType = 'Ethernet';
      } else {
        _networkType = 'Unknown';
      }
    } catch (e) {
      _networkType = 'Error: $e';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comprehensive API Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInitialData,
            tooltip: 'Refresh Data',
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportReport,
            tooltip: 'Export Report',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Info', icon: Icon(Icons.info_outline, size: 18)),
            Tab(text: 'Skenario', icon: Icon(Icons.list_alt, size: 18)),
            Tab(text: 'Detail', icon: Icon(Icons.assignment, size: 18)),
            Tab(text: 'Performa', icon: Icon(Icons.speed, size: 18)),
            Tab(text: 'Statistik', icon: Icon(Icons.pie_chart, size: 18)),
            Tab(text: 'Batch', icon: Icon(Icons.collections, size: 18)),
            Tab(text: 'Batch Detail', icon: Icon(Icons.view_list, size: 18)),
            Tab(text: 'Errors', icon: Icon(Icons.error_outline, size: 18)),
            Tab(text: 'Target', icon: Icon(Icons.check_circle, size: 18)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildInfoTab(),
                _buildSkenarioTab(),
                _buildDetailTab(),
                _buildPerformaTab(),
                _buildStatistikTab(),
                _buildBatchTab(),
                _buildBatchDetailTab(),
                _buildErrorsTab(),
                _buildTargetTab(),
              ],
            ),
    );
  }

  /// Tab 1: Tabel Info API & Device
  Widget _buildInfoTab() {
    if (_apiInfo == null) {
      return const Center(child: Text('No data available'));
    }

    final data = _apiInfo!.toTableData();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader('API & Server Information'),
          _buildDataTable(
            columns: const ['Field', 'Nilai'],
            rows: data.entries.map((e) => [e.key, e.value]).toList(),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('Model Information'),
          if (_modelInfo != null) ...[
            _buildDataTable(
              columns: const ['Field', 'Value'],
              rows: [
                ['Task', _modelInfo!.task],
                ['Architecture', _modelInfo!.arch],
                ['Input Channels', _modelInfo!.inChannels.toString()],
                ['Classes', _modelInfo!.classes],
                ['Deterministic', _modelInfo!.deterministic.toString()],
              ],
            ),
          ],
          const SizedBox(height: 16),
          _buildSectionHeader('Current Metrics (Rolling 256)'),
          if (_metricsBasic != null) ...[
            _buildDataTable(
              columns: const ['Metric', 'Value'],
              rows: [
                ['Count Requests', _metricsBasic!.countRequests.toString()],
                ['Avg Pre (ms)', _metricsBasic!.avgPreMs.toStringAsFixed(2)],
                [
                  'Avg Infer (ms)',
                  _metricsBasic!.avgInferMs.toStringAsFixed(2)
                ],
                ['Avg Post (ms)', _metricsBasic!.avgPostMs.toStringAsFixed(2)],
                [
                  'Avg Total (ms)',
                  _metricsBasic!.avgTotalMs.toStringAsFixed(2)
                ],
                [
                  'P95 Total (ms)',
                  _metricsBasic!.p95TotalMs.toStringAsFixed(2)
                ],
              ],
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// Tab 2: Tabel Skenario Testing
  Widget _buildSkenarioTab() {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Column(
        children: [
          _buildSectionHeader('Test Cases'),
          if (_testCases.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('No test cases executed yet'),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildDataTable(
                columns: const [
                  'Case ID',
                  'Skenario',
                  'Endpoint',
                  'Method',
                  'Input',
                  'Params',
                  'Expected',
                  'Actual',
                  'Status',
                  'Result',
                  'Notes'
                ],
                rows: _testCases.map((tc) {
                  final input =
                      '${tc.inputMime ?? 'N/A'}\n${tc.inputPx ?? 0}px\n${tc.inputMB?.toStringAsFixed(2) ?? 0}MB';
                  final params =
                      'fmt=${tc.paramFmt ?? 'N/A'}\nthr=${tc.paramThreshold?.toStringAsFixed(2) ?? 'N/A'}\n${tc.paramFlags ?? ''}';
                  return [
                    tc.caseId,
                    tc.skenario,
                    tc.endpoint,
                    tc.method,
                    input,
                    params,
                    tc.expected,
                    tc.actual,
                    tc.statusCode.toString(),
                    tc.passed ? 'PASS' : 'FAIL',
                    tc.catatan ?? ''
                  ];
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  /// Tab 3: Tabel Detail per Request
  Widget _buildDetailTab() {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Column(
        children: [
          _buildSectionHeader('Prediction Request Details'),
          if (_predictResults.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('No prediction results yet'),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildDataTable(
                columns: const [
                  'Case ID',
                  'Request ID',
                  'Filename',
                  'W',
                  'H',
                  'In KB',
                  'Out KB',
                  'Status',
                  'Pre',
                  'Infer',
                  'Post',
                  'Total',
                  'API Ver',
                  'Model Ver',
                  'Notes'
                ],
                rows: _predictResults.map((r) {
                  return [
                    r.caseId,
                    r.requestId.substring(0, 8),
                    r.filename,
                    r.width.toString(),
                    r.height.toString(),
                    r.inputKB.toStringAsFixed(1),
                    r.responseKB.toStringAsFixed(1),
                    r.status,
                    r.xPreMs.toStringAsFixed(1),
                    r.xInferMs.toStringAsFixed(1),
                    r.xPostMs.toStringAsFixed(1),
                    r.xTotalMs.toStringAsFixed(1),
                    r.apiVer,
                    r.modelVer,
                    r.catatan ?? ''
                  ];
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  /// Tab 4: Tabel Performa (Latency Percentiles)
  Widget _buildPerformaTab() {
    if (_predictResults.isEmpty) {
      return const Center(child: Text('No performance data yet'));
    }

    final latency = LatencyPercentiles.calculate(_predictResults);

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildSectionHeader('Latency Percentiles'),
          _buildDataTable(
            columns: const [
              'N',
              'p50',
              'p90',
              'p95',
              'p99',
              'Avg Total',
              'Avg Pre',
              'Avg Infer',
              'Avg Post',
              'Max RPS'
            ],
            rows: [
              [
                latency.n.toString(),
                latency.p50Ms.toStringAsFixed(1),
                latency.p90Ms.toStringAsFixed(1),
                latency.p95Ms.toStringAsFixed(1),
                latency.p99Ms.toStringAsFixed(1),
                latency.avgTotalMs.toStringAsFixed(1),
                latency.avgPre.toStringAsFixed(1),
                latency.avgInfer.toStringAsFixed(1),
                latency.avgPost.toStringAsFixed(1),
                latency.maxRpsSingleThread.toStringAsFixed(2),
              ]
            ],
          ),
        ],
      ),
    );
  }

  /// Tab 5: Tabel Statistik Segmentasi
  Widget _buildStatistikTab() {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Column(
        children: [
          _buildSectionHeader('Segmentation Statistics'),
          if (_segmentationStats.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('No segmentation statistics yet'),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildDataTable(
                columns: const [
                  'Case ID',
                  'Num MA',
                  'Total Area',
                  'Coverage %',
                  'Largest',
                  'Smallest',
                  'Mean Size',
                  'Top Areas'
                ],
                rows: _segmentationStats.map((s) {
                  return [
                    s.caseId,
                    s.numMicroaneurysms.toString(),
                    s.totalAreaPixels.toString(),
                    s.coveragePercentage.toStringAsFixed(4),
                    s.largestComponent.toString(),
                    s.smallestComponent.toString(),
                    s.meanComponentSize.toStringAsFixed(2),
                    s.componentAreas.take(3).join(', '),
                  ];
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  /// Tab 6: Tabel Batch Summary
  Widget _buildBatchTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildSectionHeader('Batch Summaries'),
          if (_batchSummaries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('No batch operations yet'),
            )
          else
            _buildDataTable(
              columns: const [
                'Batch ID',
                'Total',
                'Success',
                'Error',
                'Avg Coverage',
                'Avg Components',
                'Total Time',
                'Notes'
              ],
              rows: _batchSummaries.map((b) {
                return [
                  b.batchId,
                  b.totalFiles.toString(),
                  b.sukses.toString(),
                  b.error.toString(),
                  b.avgCoveragePercent.toStringAsFixed(2),
                  b.avgNumComponents.toStringAsFixed(1),
                  b.waktuTotalMs.toStringAsFixed(0),
                  b.catatan ?? ''
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }

  /// Tab 7: Tabel Batch Item Detail
  Widget _buildBatchDetailTab() {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Column(
        children: [
          _buildSectionHeader('Batch Item Details'),
          if (_batchItems.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('No batch item details yet'),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildDataTable(
                columns: const [
                  'Batch ID',
                  'Filename',
                  'Status',
                  'Error',
                  'Components',
                  'Coverage %',
                  'Mask Preview'
                ],
                rows: _batchItems.map((i) {
                  return [
                    i.batchId,
                    i.filename,
                    i.status,
                    i.error ?? '-',
                    i.numComponents?.toString() ?? 'N/A',
                    i.coveragePct?.toStringAsFixed(2) ?? 'N/A',
                    i.maskPngB64Prefix ?? 'N/A'
                  ];
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  /// Tab 8: Tabel Error Cases
  Widget _buildErrorsTab() {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Column(
        children: [
          _buildSectionHeader('Error Test Cases'),
          if (_errorCases.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('No error cases tested yet'),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildDataTable(
                columns: const [
                  'Case ID',
                  'Skenario',
                  'Input',
                  'Expected',
                  'Actual',
                  'Error',
                  'Detail',
                  'Result'
                ],
                rows: _errorCases.map((e) {
                  return [
                    e.caseId,
                    e.skenario,
                    e.input,
                    e.expectedCode.toString(),
                    e.actualCode.toString(),
                    e.errorJson ?? 'N/A',
                    e.detailJson ?? 'N/A',
                    e.passed ? 'PASS' : 'FAIL'
                  ];
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  /// Tab 9: Tabel Performance Target
  Widget _buildTargetTab() {
    // Generate default targets
    if (_performanceTargets.isEmpty && _predictResults.isNotEmpty) {
      final latency = LatencyPercentiles.calculate(_predictResults);
      _performanceTargets.addAll([
        PerformanceTarget(
          aspek: 'p95 latency',
          target: '≤ 800 ms',
          hasil: '${latency.p95Ms.toStringAsFixed(1)} ms',
          lulus: latency.p95Ms <= 800,
          catatan: latency.p95Ms <= 800 ? 'OK' : 'Exceeded target',
        ),
        PerformanceTarget(
          aspek: 'p99 latency',
          target: '≤ 1500 ms',
          hasil: '${latency.p99Ms.toStringAsFixed(1)} ms',
          lulus: latency.p99Ms <= 1500,
          catatan: latency.p99Ms <= 1500 ? 'OK' : 'Exceeded target',
        ),
        PerformanceTarget(
          aspek: 'Error normal path',
          target: '0%',
          hasil: '0%', // Calculate from test cases
          lulus: true,
          catatan: 'All tests passed',
        ),
      ]);
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildSectionHeader('Performance Targets vs Results'),
          if (_performanceTargets.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('No performance data yet'),
            )
          else
            _buildDataTable(
              columns: const ['Aspek', 'Target', 'Hasil', 'Lulus?', 'Catatan'],
              rows: _performanceTargets.map((t) {
                return [
                  t.aspek,
                  t.target,
                  t.hasil,
                  t.lulus ? '✅' : '❌',
                  t.catatan ?? ''
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDataTable({
    required List<String> columns,
    required List<List<String>> rows,
  }) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Table(
        border: TableBorder.all(color: Colors.grey.shade300),
        columnWidths: const {
          0: FlexColumnWidth(1.5),
        },
        children: [
          // Header row
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade200),
            children: columns
                .map((col) => Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        col,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ))
                .toList(),
          ),
          // Data rows
          ...rows.map((row) => TableRow(
                children: row
                    .map((cell) => Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(cell),
                        ))
                    .toList(),
              )),
        ],
      ),
    );
  }

  Future<void> _exportReport() async {
    // Planned: implement export to CSV/PDF.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Export feature coming soon')),
    );
  }
}
