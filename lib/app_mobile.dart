import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'models/test_result.dart';
import 'pages/home_page.dart';
import 'pages/performance_page.dart';
import 'pages/metrics_page.dart';
import 'pages/batch_prediction_page.dart';
import 'pages/test_runner_page.dart';
import 'services/api_client.dart';

Widget buildApp() => const MyApp();

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MA Segmentation Tester',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;
  final List<TestResult> _testHistory = [];
  Map<String, dynamic>? _modelInfo;

  @override
  void initState() {
    super.initState();
    _loadModelInfo();
  }

  Future<void> _loadModelInfo() async {
    try {
      final baseUrl = dotenv.env['API_BASE'] ?? '';
      if (baseUrl.isEmpty) {
        debugPrint('API_BASE is empty in .env');
        return;
      }

      debugPrint('Loading model info from: $baseUrl');
      final api = ApiClient(baseUrl);

      try {
        final health = await api.healthz();
        debugPrint('Health check OK: ${health['ready']}');
      } catch (e) {
        debugPrint('Health check failed: $e');
      }

      final info = await api.modelInfo();
      debugPrint('Model info loaded: ${info['arch']}');

      setState(() {
        _modelInfo = info;
      });
    } catch (e, stackTrace) {
      debugPrint('Failed to load model info: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  void _onTestComplete(TestResult result) {
    setState(() {
      _testHistory.add(result);
    });
  }

  void _showModelInfo() {
    if (_modelInfo == null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Connection Error'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Model info not available.'),
              const SizedBox(height: 8),
              const Text(
                'Please check:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('• API server is running'),
              const Text('• API_BASE URL is correct in .env'),
              const Text('• Internet connection is active'),
              const SizedBox(height: 16),
              Text(
                'Current API URL:\n${dotenv.env['API_BASE'] ?? 'Not set'}',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _loadModelInfo();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Retrying connection...')),
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Model Information'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _infoRow('Task', _modelInfo!['task'] ?? 'N/A'),
              _infoRow('Architecture', _modelInfo!['arch'] ?? 'N/A'),
              _infoRow(
                  'Input Channels', '${_modelInfo!['in_channels'] ?? 'N/A'}'),
              _infoRow('Classes', _modelInfo!['classes'] ?? 'N/A'),
              _infoRow('Model Version', _modelInfo!['model_version'] ?? 'N/A'),
              _infoRow('API Version', _modelInfo!['api_version'] ?? 'N/A'),
              _infoRow('Device', _modelInfo!['device'] ?? 'N/A'),
              const Divider(),
              const Text(
                'Checkpoint SHA256:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 4),
              SelectableText(
                _modelInfo!['checkpoint_sha256'] ?? 'N/A',
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MA Segmentation Tester'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Model Info',
            onPressed: _showModelInfo,
          ),
          if (_currentIndex == 4 && _testHistory.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear History',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear History'),
                    content: const Text(
                        'Are you sure you want to clear all test history?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() => _testHistory.clear());
                          Navigator.pop(context);
                        },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const TestRunnerPage(),
          const BatchPredictionPage(),
          HomePage(onTestComplete: _onTestComplete),
          const MetricsPage(),
          PerformancePage(results: _testHistory),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
            label: 'API Test',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: 'P. Batch',
          ),
          NavigationDestination(
            icon: Icon(Icons.image_outlined),
            selectedIcon: Icon(Icons.image),
            label: 'P. Single',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Metrics',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Performance',
          ),
        ],
      ),
    );
  }
}
