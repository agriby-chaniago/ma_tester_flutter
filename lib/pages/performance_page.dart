import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/test_result.dart';

class PerformancePage extends StatelessWidget {
  final List<TestResult> results;

  const PerformancePage({super.key, required this.results});

  @override
  Widget build(BuildContext context) {
    final successResults = results.where((r) => r.success).toList();

    if (successResults.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.analytics_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No test data yet',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Run some tests to see performance metrics',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Performance data from your test history (single predictions only, batch predictions tracked separately)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Summary Stats
          _buildSummaryCards(successResults),
          const SizedBox(height: 24),

          // Line Chart
          const Text(
            'Performance Over Time',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: _buildLineChart(successResults),
          ),
          const SizedBox(height: 24),

          // Test History
          const Text(
            'Test History',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildHistoryList(successResults),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(List<TestResult> results) {
    final clientTimes = results
        .where((r) => r.clientTotalMs != null)
        .map((r) => r.clientTotalMs!)
        .toList();
    final serverTimes = results
        .where((r) => r.serverInferMs != null)
        .map((r) => r.serverInferMs!)
        .toList();
    final maCounts = results
        .where((r) => r.numMicroaneurysms != null)
        .map((r) => r.numMicroaneurysms!)
        .toList();

    final avgClient = clientTimes.isEmpty
        ? 0
        : clientTimes.reduce((a, b) => a + b) / clientTimes.length;
    final avgServer = serverTimes.isEmpty
        ? 0
        : serverTimes.reduce((a, b) => a + b) / serverTimes.length;
    final avgMA = maCounts.isEmpty
        ? 0.0
        : maCounts.reduce((a, b) => a + b) / maCounts.length;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Total Tests',
                results.length.toString(),
                Icons.check_circle,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatCard(
                'Avg Client',
                '${avgClient.round()} ms',
                Icons.timer,
                Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatCard(
                'Avg Server',
                avgServer > 0 ? '${avgServer.round()} ms' : 'N/A',
                Icons.speed,
                Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Avg MAs',
                avgMA > 0 ? avgMA.toStringAsFixed(1) : 'N/A',
                Icons.visibility,
                Colors.red,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatCard(
                'Total MAs',
                maCounts.isEmpty
                    ? 'N/A'
                    : maCounts.reduce((a, b) => a + b).toString(),
                Icons.analytics,
                Colors.purple,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(child: SizedBox()), // spacer
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart(List<TestResult> results) {
    final clientSpots = <FlSpot>[];
    final serverSpots = <FlSpot>[];

    for (int i = 0; i < results.length; i++) {
      if (results[i].clientTotalMs != null) {
        clientSpots
            .add(FlSpot(i.toDouble(), results[i].clientTotalMs!.toDouble()));
      }
      if (results[i].serverInferMs != null) {
        serverSpots
            .add(FlSpot(i.toDouble(), results[i].serverInferMs!.toDouble()));
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: true,
              horizontalInterval: 500,
              verticalInterval: 1,
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 50,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      '${value.toInt()} ms',
                      style: const TextStyle(fontSize: 10),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      '#${value.toInt() + 1}',
                      style: const TextStyle(fontSize: 10),
                    );
                  },
                ),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: true),
            lineBarsData: [
              if (clientSpots.isNotEmpty)
                LineChartBarData(
                  spots: clientSpots,
                  isCurved: true,
                  color: Colors.blue,
                  barWidth: 3,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.blue.withAlpha(26), // 0.1 * 255 ≈ 26
                  ),
                ),
              if (serverSpots.isNotEmpty)
                LineChartBarData(
                  spots: serverSpots,
                  isCurved: true,
                  color: Colors.orange,
                  barWidth: 3,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.orange.withAlpha(26), // 0.1 * 255 ≈ 26
                  ),
                ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    final isClient = spot.barIndex == 0;
                    return LineTooltipItem(
                      '${isClient ? 'Client' : 'Server'}\n${spot.y.toInt()} ms',
                      TextStyle(
                        color: isClient ? Colors.blue : Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  }).toList();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryList(List<TestResult> results) {
    final reversed = results.reversed.toList();

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: reversed.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final result = reversed[index];
          final time = result.timestamp;
          final timeStr =
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';

          return ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: Colors.blue.withAlpha(26), // 0.1 * 255 ≈ 26
              child: Text(
                '#${reversed.length - index}',
                style: const TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ),
            title: Row(
              children: [
                Text('Client: ${result.clientTotalMs ?? '-'} ms'),
                const SizedBox(width: 16),
                if (result.serverInferMs != null)
                  Text(
                    'Server: ${result.serverInferMs} ms',
                    style: const TextStyle(color: Colors.orange),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Threshold: ${result.threshold?.toStringAsFixed(2) ?? '-'} • $timeStr',
                  style: const TextStyle(fontSize: 11),
                ),
                if (result.numMicroaneurysms != null)
                  Text(
                    'MAs: ${result.numMicroaneurysms} • Coverage: ${result.coveragePercentage?.toStringAsFixed(4)}%',
                    style: const TextStyle(fontSize: 11, color: Colors.blue),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
