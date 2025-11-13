import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_client.dart';
import '../models/test_result.dart';

class HomePage extends StatefulWidget {
  final Function(TestResult) onTestComplete;

  const HomePage({super.key, required this.onTestComplete});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late TextEditingController _baseUrlCtrl;
  late TextEditingController _thresCtrl;
  Uint8List? _inputBytes;
  Uint8List? _maskBytes;
  Uint8List? _overlayBytes;
  Map<String, dynamic>? _lastJson;
  Map<String, dynamic>? _statistics;
  bool _busy = false;
  int? _clientTotalMs;
  int? _serverInferMs;
  bool _showOverlay = true; // Toggle untuk overlay
  String _selectedFormat =
      'json'; // Format output: png | proba | compact | json
  bool _requestProba = false; // Request lossless probability map
  String? _outputType; // 'mask' atau 'probability_u8' untuk fmt=png/proba
  String? _requestId; // UUID tracing dari response

  final _picker = ImagePicker();
  XFile? _pickedFile;

  @override
  void initState() {
    super.initState();
    _baseUrlCtrl = TextEditingController(text: dotenv.env['API_BASE']);
    _thresCtrl = TextEditingController(text: '0.75'); // MATCH training default
  }

  Future<void> _pickImage(ImageSource src) async {
    final x = await _picker.pickImage(
      source: src,
      imageQuality: 92,
      maxWidth: 1536,
    );
    if (x == null) return;

    // Validasi ukuran file (max 20MB)
    final bytes = await x.readAsBytes();
    final sizeMB = bytes.length / (1024 * 1024);

    if (sizeMB > 20.0) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('File Too Large'),
          content: Text(
            'Image size is ${sizeMB.toStringAsFixed(2)} MB.\n'
            'Maximum allowed size is 20 MB.\n\n'
            'Please select a smaller image or reduce the image quality.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _pickedFile = x;
      _inputBytes = bytes;
      _maskBytes = null;
      _overlayBytes = null;
      _lastJson = null;
      _statistics = null;
      _clientTotalMs = null;
      _serverInferMs = null;
    });
  }

  Future<void> _predict() async {
    if (_pickedFile == null) return;
    final base = _baseUrlCtrl.text.trim();
    final api = ApiClient(
      base,
      timeoutMs: int.tryParse(dotenv.env['TIMEOUT_MS'] ?? '') ?? 90000,
    );

    setState(() {
      _busy = true;
      _maskBytes = null;
      _overlayBytes = null;
      _statistics = null;
      _clientTotalMs = null;
      _serverInferMs = null;
      _lastJson = null;
      _outputType = null;
      _requestId = null;
    });

    try {
      final thr = double.tryParse(_thresCtrl.text.trim()) ?? 0.5;

      // Request dengan format yang dipilih
      final res = await api.predictMultipart(
        _pickedFile!.path,
        timeoutMs: int.tryParse(dotenv.env['TIMEOUT_MS'] ?? '') ?? 90000,
        threshold: thr,
        fmt: _selectedFormat, // png | proba | compact | json
        returnOverlay: _showOverlay && _selectedFormat == 'json',
        proba: _requestProba && _selectedFormat == 'json',
      );

      setState(() {
        _maskBytes = res['mask'] as Uint8List?;
        _overlayBytes = res['overlay'] as Uint8List?;
        _lastJson = res['json'] as Map<String, dynamic>?;
        _statistics = res['statistics'] as Map<String, dynamic>?;
        _clientTotalMs = res['clientTotalMs'] as int?;
        _serverInferMs = res['serverInferMs'] as int?;
        _outputType = res['outputType'] as String?;
        _requestId = res['requestId'] as String?;
      });

      // Parse statistics untuk history
      final stats = _statistics;
      widget.onTestComplete(TestResult(
        timestamp: DateTime.now(),
        clientTotalMs: _clientTotalMs,
        serverInferMs: _serverInferMs,
        threshold: thr,
        success: true,
        numMicroaneurysms: stats?['num_microaneurysms'] as int?,
        totalAreaPixels: stats?['total_area_pixels'] as int?,
        coveragePercentage: (stats?['coverage_percentage'] as num?)?.toDouble(),
        largestComponent: stats?['largest_component'] as int?,
        meanComponentSize: (stats?['mean_component_size'] as num?)?.toDouble(),
      ));
    } catch (e) {
      widget.onTestComplete(TestResult(
        timestamp: DateTime.now(),
        threshold: double.tryParse(_thresCtrl.text.trim()),
        success: false,
      ));

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Predict Error'),
          content: Text(e.toString()),
        ),
      );
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _thresCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Base URL input
          TextField(
            controller: _baseUrlCtrl,
            decoration: const InputDecoration(
              labelText: 'API Base URL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Threshold input
          TextField(
            controller: _thresCtrl,
            decoration: const InputDecoration(
              labelText: 'Threshold (0.0 - 1.0)',
              helperText: 'Lower = more sensitive',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 8),

          // Overlay toggle
          SwitchListTile(
            title: const Text('Request Overlay Image'),
            subtitle: const Text('Show MA detections overlaid on original'),
            value: _showOverlay,
            onChanged: _selectedFormat == 'json'
                ? (val) {
                    setState(() => _showOverlay = val);
                  }
                : null, // disabled jika bukan format json
          ),
          const SizedBox(height: 8),

          // Format selector
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Output Format:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('PNG'),
                        selected: _selectedFormat == 'png',
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedFormat = 'png');
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Proba'),
                        selected: _selectedFormat == 'proba',
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedFormat = 'proba');
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Compact'),
                        selected: _selectedFormat == 'compact',
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedFormat = 'compact');
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('JSON'),
                        selected: _selectedFormat == 'json',
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedFormat = 'json');
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getFormatDescription(),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Proba toggle (hanya untuk format json)
          if (_selectedFormat == 'json')
            SwitchListTile(
              title: const Text('Request Lossless Probability'),
              subtitle: const Text('Include .npy probability map (base64)'),
              value: _requestProba,
              onChanged: (val) {
                setState(() => _requestProba = val);
              },
            ),
          const SizedBox(height: 16),

          // Image picker button
          ElevatedButton.icon(
            onPressed: _busy ? null : () => _pickImage(ImageSource.gallery),
            icon: const Icon(Icons.photo_library),
            label: const Text('Select Image from Gallery'),
          ),
          const SizedBox(height: 16),

          // Predict button
          FilledButton.icon(
            onPressed: (_busy || _pickedFile == null) ? null : _predict,
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload),
            label: Text(_busy ? 'Processing...' : 'Predict'),
          ),
          const SizedBox(height: 24),

          // Display input image
          if (_inputBytes != null) ...[
            const Text(
              'Input Image:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(_inputBytes!, fit: BoxFit.contain),
            ),
            const SizedBox(height: 24),
          ],

          // Display mask
          if (_maskBytes != null) ...[
            Row(
              children: [
                const Text(
                  'Segmentation Result:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (_outputType != null) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      _outputType == 'probability_u8'
                          ? 'Probability Map'
                          : 'Binary Mask',
                      style: const TextStyle(fontSize: 11),
                    ),
                    backgroundColor: _outputType == 'probability_u8'
                        ? Colors.purple.shade100
                        : Colors.blue.shade100,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(_maskBytes!, fit: BoxFit.contain),
            ),
            const SizedBox(height: 24),
          ],

          // Display overlay (jika ada)
          if (_overlayBytes != null) ...[
            const Text(
              'Overlay (MA Detection):',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(_overlayBytes!, fit: BoxFit.contain),
            ),
            const SizedBox(height: 24),
          ],

          // Display statistics
          if (_statistics != null) ...[
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.analytics, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        const Text(
                          'Detection Statistics:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    _buildStatRow('Microaneurysms',
                        '${_statistics!['num_microaneurysms'] ?? 0}'),
                    _buildStatRow('Total Area',
                        '${_statistics!['total_area_pixels'] ?? 0} px'),
                    _buildStatRow(
                      'Coverage',
                      '${(_statistics!['coverage_percentage'] as num?)?.toStringAsFixed(4) ?? '0'}%',
                    ),
                    _buildStatRow('Largest Component',
                        '${_statistics!['largest_component'] ?? 0} px'),
                    _buildStatRow(
                      'Mean Size',
                      '${(_statistics!['mean_component_size'] as num?)?.toStringAsFixed(2) ?? '0'} px',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Display latency
          if (_clientTotalMs != null || _serverInferMs != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.timer, color: Colors.blue),
                        const SizedBox(width: 8),
                        const Text(
                          'Timing Information:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_clientTotalMs != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 32),
                        child: Text(
                          'Client Total: $_clientTotalMs ms',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    if (_serverInferMs != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 32, top: 4),
                        child: Text(
                          'Server Infer: $_serverInferMs ms',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    if (_requestId != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 32, top: 8),
                        child: Text(
                          'Request ID: $_requestId',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Display JSON response
          if (_lastJson != null) ...[
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.code, color: Colors.blue),
                title: const Text(
                  'Response JSON',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'Tap to expand (may contain large base64 data)',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                children: [
                  Container(
                    constraints: const BoxConstraints(maxHeight: 400),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        _formatJson(_lastJson!),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _getFormatDescription() {
    switch (_selectedFormat) {
      case 'png':
        return 'Binary mask PNG (~5-10KB, no statistics)';
      case 'proba':
        return 'Probability map PNG 0-255 (soft mask, no threshold)';
      case 'compact':
        return 'JSON minimal: mask + timing only';
      case 'json':
        return 'JSON lengkap: mask + statistics + overlay optional';
      default:
        return '';
    }
  }

  String _formatJson(Map<String, dynamic> json) {
    // Format JSON dengan memotong base64 data yang panjang
    final Map<String, dynamic> formatted = {};

    json.forEach((key, value) {
      if (value is String && value.startsWith('data:image/')) {
        // Potong base64 image data
        final commaIndex = value.indexOf(',');
        if (commaIndex > 0 && value.length > commaIndex + 100) {
          formatted[key] =
              '${value.substring(0, commaIndex + 100)}... [truncated ${((value.length - commaIndex) / 1024).toStringAsFixed(1)} KB]';
        } else {
          formatted[key] = value;
        }
      } else if (value is String && value.length > 500) {
        // Potong string panjang lainnya (seperti proba_npy_b64)
        formatted[key] =
            '${value.substring(0, 100)}... [truncated ${(value.length / 1024).toStringAsFixed(1)} KB]';
      } else if (value is Map) {
        // Recursive untuk nested maps
        formatted[key] = value;
      } else {
        formatted[key] = value;
      }
    });

    return formatted.toString();
  }
}
