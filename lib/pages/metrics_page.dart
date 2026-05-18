import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/api_client.dart';

class MetricsPage extends StatefulWidget {
  const MetricsPage({super.key});

  @override
  State<MetricsPage> createState() => _MetricsPageState();
}

class _MetricsPageState extends State<MetricsPage> {
  Map<String, dynamic>? _metrics;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final baseUrl = dotenv.env['API_BASE'] ?? '';
      if (baseUrl.isEmpty) {
        throw Exception('API_BASE not configured');
      }

      final api = ApiClient(baseUrl);
      final metrics = await api.metricsBasic();

      if (!mounted) return;
      setState(() {
        _metrics = metrics;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Metrics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadMetrics,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _metrics == null
                  ? const Center(child: Text('No metrics available'))
                  : Column(
                      children: [
                        // Info banner
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          color: Colors.blue.shade50,
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 20, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Rolling statistics from last 256 requests (includes both /predict and /predict_batch)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: _buildMetrics()),
                      ],
                    ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Failed to load metrics',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadMetrics,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetrics() {
    final countRequests = _metrics!['count_requests'] as int? ?? 0;
    final avgPreMs = _metrics!['avg_pre_ms'] as num? ?? 0;
    final avgInferMs = _metrics!['avg_infer_ms'] as num? ?? 0;
    final avgPostMs = _metrics!['avg_post_ms'] as num? ?? 0;
    final avgTotalMs = _metrics!['avg_total_ms'] as num? ?? 0;
    final p95TotalMs = _metrics!['p95_total_ms'] as num? ?? 0;

    // Helper untuk menghindari infinity/NaN
    double safePercentage(num numerator, num denominator) {
      if (denominator == 0 || !denominator.isFinite) return 0.0;
      final result = (numerator / denominator * 100);
      if (!result.isFinite) return 0.0;
      return result;
    }

    String safeThroughput() {
      if (countRequests == 0 || avgTotalMs == 0 || !avgTotalMs.isFinite) {
        return '0.00 req/s';
      }
      final throughput = countRequests / (avgTotalMs / 1000);
      if (!throughput.isFinite) return '0.00 req/s';
      return '${throughput.toStringAsFixed(2)} req/s';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Summary Card
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.analytics, size: 48, color: Colors.blue),
                  const SizedBox(height: 12),
                  Text(
                    'Rolling Statistics',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Last 256 requests',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade700,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$countRequests',
                      style:
                          Theme.of(context).textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Total Requests Processed'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Timing Breakdown
          const Text(
            'Average Timing Breakdown',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Preprocessing',
                  '${avgPreMs.toStringAsFixed(1)} ms',
                  Icons.image_outlined,
                  Colors.green,
                  percentage: safePercentage(avgPreMs, avgTotalMs),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  'Inference',
                  '${avgInferMs.toStringAsFixed(1)} ms',
                  Icons.psychology,
                  Colors.orange,
                  percentage: safePercentage(avgInferMs, avgTotalMs),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Postprocessing',
                  '${avgPostMs.toStringAsFixed(1)} ms',
                  Icons.tune,
                  Colors.purple,
                  percentage: safePercentage(avgPostMs, avgTotalMs),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  'Total Average',
                  '${avgTotalMs.toStringAsFixed(1)} ms',
                  Icons.timer,
                  Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Percentiles
          const Text(
            'Latency Percentiles',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildPercentileRow('P50 (Median)', avgTotalMs),
                  const Divider(),
                  _buildPercentileRow('P95', p95TotalMs),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Performance Indicators
          const Text(
            'Performance Indicators',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildIndicatorRow(
                    'Throughput',
                    safeThroughput(),
                    Icons.speed,
                  ),
                  const Divider(),
                  _buildIndicatorRow(
                    'Inference Ratio',
                    '${safePercentage(avgInferMs, avgTotalMs).toStringAsFixed(1)}%',
                    Icons.pie_chart,
                  ),
                  const Divider(),
                  _buildIndicatorRow(
                    'Overhead',
                    '${safePercentage(avgPreMs + avgPostMs, avgTotalMs).toStringAsFixed(1)}%',
                    Icons.settings_suggest,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Last Updated
          Text(
            'Last updated: ${DateTime.now().toString().substring(0, 19)}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    IconData icon,
    Color color, {
    double? percentage,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            if (percentage != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: percentage / 100,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
              const SizedBox(height: 4),
              Text(
                '${percentage.toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPercentileRow(String label, num value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          Text(
            '${value.toStringAsFixed(1)} ms',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicatorRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
