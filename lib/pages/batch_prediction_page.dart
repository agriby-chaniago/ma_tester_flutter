import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/api_client.dart';

class BatchPredictionPage extends StatefulWidget {
  const BatchPredictionPage({super.key});

  @override
  State<BatchPredictionPage> createState() => _BatchPredictionPageState();
}

class _BatchPredictionPageState extends State<BatchPredictionPage> {
  final ImagePicker _picker = ImagePicker();
  List<XFile> _selectedImages = [];
  final List<BatchResult> _results = [];
  bool _processing = false;
  double _threshold = 0.75; // MATCH training default

  Future<void> _pickImages() async {
    try {
      final images = await _picker.pickMultiImage(
        imageQuality: 100,
      );

      if (images.isEmpty) return;

      // Validasi ukuran file untuk setiap gambar (max 20MB)
      final List<XFile> validImages = [];
      final List<String> tooLargeFiles = [];

      for (final image in images) {
        final bytes = await image.readAsBytes();
        final sizeMB = bytes.length / (1024 * 1024);

        if (sizeMB <= 20.0) {
          validImages.add(image);
        } else {
          tooLargeFiles.add('${image.name} (${sizeMB.toStringAsFixed(1)} MB)');
        }
      }

      // Tampilkan warning jika ada file yang terlalu besar
      if (tooLargeFiles.isNotEmpty && mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Some Files Too Large'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'The following files exceed 20 MB and were excluded:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...tooLargeFiles.map((f) => Text('• $f')),
                  const SizedBox(height: 12),
                  Text(
                    '${validImages.length} of ${images.length} images selected.',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }

      if (validImages.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No valid images selected. All files exceed 20 MB.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (validImages.length > 10) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maximum 10 images allowed. Selecting first 10.'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() {
          _selectedImages = validImages.take(10).toList();
        });
      } else {
        setState(() {
          _selectedImages = validImages;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking images: $e')),
      );
    }
  }

  Future<void> _processBatch() async {
    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select images first')),
      );
      return;
    }

    setState(() {
      _processing = true;
      _results.clear();
    });

    try {
      final baseUrl = dotenv.env['API_BASE'] ?? '';
      if (baseUrl.isEmpty) {
        throw Exception('API_BASE not configured');
      }

      final api = ApiClient(baseUrl);

      // NOTE: Ada 2 cara untuk batch processing:
      //
      // Option 1: Gunakan /predict_batch endpoint (lebih cepat, tapi kurang detail)
      //   final filePaths = _selectedImages.map((img) => img.path).toList();
      //   final batchResult = await api.predictBatch(
      //     filePaths,
      //     threshold: _threshold,
      //     fmt: 'stats', // atau 'compact' untuk mendapat mask
      //   );
      //   // Process batchResult['results'] list
      //
      // Option 2: Process satu per satu dengan /predict (lebih lambat, detail penuh)
      //   - Mendapat timing per image
      //   - Mendapat statistics detail
      //   - Progress tracking per image
      //   - Implementasi di bawah ini

      // Process images one by one to get detailed metrics
      for (int i = 0; i < _selectedImages.length; i++) {
        final image = _selectedImages[i];

        setState(() {
          _results.add(BatchResult(
            imageName: image.name,
            status: 'processing',
            progress: (i / _selectedImages.length),
          ));
        });

        try {
          final startTime = DateTime.now();

          final response = await api.predictMultipart(
            image.path,
            fmt: 'json',
            threshold: _threshold,
            returnOverlay: false,
            proba: false,
          );

          final endTime = DateTime.now();
          final clientTotalMs = endTime.difference(startTime).inMilliseconds;

          // Extract statistics and metrics
          final stats = response['statistics'] as Map<String, dynamic>?;
          final timingMs = response['timing_ms'] as Map<String, dynamic>?;
          final serverInferMs = response['serverInferMs'] as int?;

          // Calculate per-image metrics if possible
          // For now, we'll show basic stats, but you can add ground truth comparison here
          final metrics = _calculateMetrics(response);

          setState(() {
            _results[i] = BatchResult(
              imageName: image.name,
              status: 'success',
              progress: 1.0,
              numMicroaneurysms: stats?['num_microaneurysms'] as int?,
              coveragePercentage:
                  (stats?['coverage_percentage'] as num?)?.toDouble(),
              clientTotalMs: clientTotalMs,
              serverInferMs: serverInferMs ?? timingMs?['infer_ms'] as int?,
              metrics: metrics,
            );
          });
        } catch (e) {
          setState(() {
            _results[i] = BatchResult(
              imageName: image.name,
              status: 'error',
              progress: 1.0,
              error: e.toString(),
            );
          });
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Processed ${_selectedImages.length} images'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _processing = false;
      });
    }
  }

  Map<String, double>? _calculateMetrics(Map<String, dynamic> response) {
    // Here you would calculate Dice, IoU, etc. if you have ground truth
    // For demonstration, we'll return null (metrics not available)
    // In a real app, you'd compare with ground truth masks

    // Example calculation if you have ground truth:
    // final predicted = response['mask_binary'];
    // final groundTruth = loadGroundTruth();
    // return {
    //   'dice': calculateDice(predicted, groundTruth),
    //   'iou': calculateIoU(predicted, groundTruth),
    //   'precision': calculatePrecision(predicted, groundTruth),
    //   'recall': calculateRecall(predicted, groundTruth),
    // };

    return null; // No ground truth available
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch Prediction'),
        actions: [
          if (_selectedImages.isNotEmpty && !_processing)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear all',
              onPressed: () {
                setState(() {
                  _selectedImages.clear();
                  _results.clear();
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Controls
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _processing ? null : _pickImages,
                        icon: const Icon(Icons.add_photo_alternate),
                        label: Text(_selectedImages.isEmpty
                            ? 'Select Images'
                            : '${_selectedImages.length} images selected'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _processing || _selectedImages.isEmpty
                            ? null
                            : _processBatch,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Process Batch'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Threshold slider
                Row(
                  children: [
                    const Icon(Icons.tune, size: 20),
                    const SizedBox(width: 8),
                    const Text('Threshold:', style: TextStyle(fontSize: 14)),
                    Expanded(
                      child: Slider(
                        value: _threshold,
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        label: _threshold.toStringAsFixed(2),
                        onChanged: _processing
                            ? null
                            : (value) {
                                setState(() {
                                  _threshold = value;
                                });
                              },
                      ),
                    ),
                    Text(
                      _threshold.toStringAsFixed(2),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Results
          Expanded(
            child: _selectedImages.isEmpty
                ? _buildEmptyState()
                : _results.isEmpty
                    ? _buildImageGrid()
                    : _buildResultsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_search, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No images selected',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Select up to 10 images to process',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _selectedImages.length,
      itemBuilder: (context, index) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(_selectedImages[index].path),
              fit: BoxFit.cover,
            ),
            Positioned(
              top: 4,
              right: 4,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: Colors.black54,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResultsList() {
    final successCount = _results.where((r) => r.status == 'success').length;
    final errorCount = _results.where((r) => r.status == 'error').length;

    // Calculate average metrics
    final successResults =
        _results.where((r) => r.status == 'success').toList();
    double? avgDice, avgIoU, avgPrecision, avgRecall;

    if (successResults.isNotEmpty) {
      final diceValues = successResults
          .where((r) => r.metrics?['dice'] != null)
          .map((r) => r.metrics!['dice']!)
          .toList();
      final iouValues = successResults
          .where((r) => r.metrics?['iou'] != null)
          .map((r) => r.metrics!['iou']!)
          .toList();
      final precisionValues = successResults
          .where((r) => r.metrics?['precision'] != null)
          .map((r) => r.metrics!['precision']!)
          .toList();
      final recallValues = successResults
          .where((r) => r.metrics?['recall'] != null)
          .map((r) => r.metrics!['recall']!)
          .toList();

      if (diceValues.isNotEmpty) {
        avgDice = diceValues.reduce((a, b) => a + b) / diceValues.length;
      }
      if (iouValues.isNotEmpty) {
        avgIoU = iouValues.reduce((a, b) => a + b) / iouValues.length;
      }
      if (precisionValues.isNotEmpty) {
        avgPrecision =
            precisionValues.reduce((a, b) => a + b) / precisionValues.length;
      }
      if (recallValues.isNotEmpty) {
        avgRecall = recallValues.reduce((a, b) => a + b) / recallValues.length;
      }
    }

    return Column(
      children: [
        // Summary Card
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blue.shade50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Batch Results Summary',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      'Success',
                      successCount.toString(),
                      Colors.green,
                      Icons.check_circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSummaryCard(
                      'Errors',
                      errorCount.toString(),
                      Colors.red,
                      Icons.error,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSummaryCard(
                      'Total',
                      _results.length.toString(),
                      Colors.blue,
                      Icons.image,
                    ),
                  ),
                ],
              ),

              // Average metrics (if available)
              if (avgDice != null ||
                  avgIoU != null ||
                  avgPrecision != null ||
                  avgRecall != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Average Metrics',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (avgDice != null)
                      Expanded(
                        child: _buildMetricChip('Dice', avgDice, Colors.blue),
                      ),
                    if (avgIoU != null)
                      Expanded(
                        child: _buildMetricChip('IoU', avgIoU, Colors.green),
                      ),
                    if (avgPrecision != null)
                      Expanded(
                        child: _buildMetricChip(
                            'Precision', avgPrecision, Colors.orange),
                      ),
                    if (avgRecall != null)
                      Expanded(
                        child: _buildMetricChip(
                            'Recall', avgRecall, Colors.purple),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // Results List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              return _buildResultCard(_results[index], index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
      String label, String value, Color color, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricChip(String label, double value, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(26), // 0.1 * 255 ≈ 26
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(77)), // 0.3 * 255 ≈ 77
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: 10, color: color.withAlpha(179)), // 0.7 * 255 ≈ 179
          ),
          Text(
            value.toStringAsFixed(3),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color.withAlpha(179), // 0.7 * 255 ≈ 179
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(BatchResult result, int index) {
    final isProcessing = result.status == 'processing';
    final isSuccess = result.status == 'success';
    final isError = result.status == 'error';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: isSuccess
              ? Colors.green
              : isError
                  ? Colors.red
                  : Colors.orange,
          child: isProcessing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Icon(
                  isSuccess ? Icons.check : Icons.error,
                  color: Colors.white,
                  size: 20,
                ),
        ),
        title: Text(
          result.imageName,
          style: const TextStyle(fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: isError
            ? Text(
                'Error: ${result.error}',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              )
            : isProcessing
                ? LinearProgressIndicator(value: result.progress)
                : Text(
                    '${result.numMicroaneurysms ?? 0} MA • ${result.coveragePercentage?.toStringAsFixed(2) ?? 0}%',
                    style: const TextStyle(fontSize: 12),
                  ),
        children: isSuccess
            ? [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Statistics
                      const Text(
                        'Statistics',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow(
                          'Microaneurysms', '${result.numMicroaneurysms}'),
                      _buildDetailRow('Coverage',
                          '${result.coveragePercentage?.toStringAsFixed(2)}%'),
                      _buildDetailRow(
                          'Client Time', '${result.clientTotalMs} ms'),
                      _buildDetailRow(
                          'Server Time', '${result.serverInferMs} ms'),

                      // Metrics (if available)
                      if (result.metrics != null &&
                          result.metrics!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 8),
                        const Text(
                          'Per-Image Metrics',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        if (result.metrics!['dice'] != null)
                          _buildDetailRow('Dice Score',
                              result.metrics!['dice']!.toStringAsFixed(4)),
                        if (result.metrics!['iou'] != null)
                          _buildDetailRow('IoU',
                              result.metrics!['iou']!.toStringAsFixed(4)),
                        if (result.metrics!['precision'] != null)
                          _buildDetailRow('Precision',
                              result.metrics!['precision']!.toStringAsFixed(4)),
                        if (result.metrics!['recall'] != null)
                          _buildDetailRow('Recall',
                              result.metrics!['recall']!.toStringAsFixed(4)),
                        if (result.metrics!['f1'] != null)
                          _buildDetailRow('F1 Score',
                              result.metrics!['f1']!.toStringAsFixed(4)),
                        if (result.metrics!['accuracy'] != null)
                          _buildDetailRow('Accuracy',
                              result.metrics!['accuracy']!.toStringAsFixed(4)),
                      ] else ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Ground truth not available for metric calculation',
                          style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                ),
              ]
            : [],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class BatchResult {
  final String imageName;
  final String status; // 'processing', 'success', 'error'
  final double progress;
  final int? numMicroaneurysms;
  final double? coveragePercentage;
  final int? clientTotalMs;
  final int? serverInferMs;
  final String? error;
  final Map<String, double>? metrics; // Dice, IoU, Precision, Recall, etc.

  BatchResult({
    required this.imageName,
    required this.status,
    this.progress = 0.0,
    this.numMicroaneurysms,
    this.coveragePercentage,
    this.clientTotalMs,
    this.serverInferMs,
    this.error,
    this.metrics,
  });
}
