import 'package:flutter/material.dart';
import '../models/test_case_detail.dart';

/// Page untuk menampilkan detail lengkap per test case
class TestCaseDetailPage extends StatefulWidget {
  final DetailedTestCase testCase;

  const TestCaseDetailPage({
    super.key,
    required this.testCase,
  });

  @override
  State<TestCaseDetailPage> createState() => _TestCaseDetailPageState();
}

class _TestCaseDetailPageState extends State<TestCaseDetailPage> {
  late DetailedTestCase _testCase;

  @override
  void initState() {
    super.initState();
    _testCase = widget.testCase;
  }

  Color _getStatusColor() {
    if (_testCase.isPassed) return Colors.green;
    if (_testCase.isFailed) return Colors.red;
    return Colors.grey;
  }

  IconData _getStatusIcon() {
    if (_testCase.isPassed) return Icons.check_circle;
    if (_testCase.isFailed) return Icons.cancel;
    return Icons.help_outline;
  }

  String _getStatusText() {
    if (_testCase.isPassed) return 'PASS';
    if (_testCase.isFailed) return 'FAIL';
    return 'PENDING';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_testCase.caseId),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            _buildHeaderCard(),
            const SizedBox(height: 16),

            // Test Details Card
            _buildTestDetailsCard(),
            const SizedBox(height: 16),

            // Verification Steps Card
            _buildVerificationStepsCard(),
            const SizedBox(height: 16),

            // Actual Results Card (if test has been run)
            if (_testCase.actualStatusCode != null) _buildActualResultsCard(),

            if (_testCase.actualStatusCode != null) const SizedBox(height: 16),

            // Notes Card
            _buildNotesCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getStatusIcon(),
                  color: _getStatusColor(),
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _testCase.caseId,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _testCase.name,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor().withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getStatusText(),
                    style: TextStyle(
                      color: _getStatusColor(),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestDetailsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📝 Test Details',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            _buildDetailRow(
                'Endpoint', '${_testCase.method} ${_testCase.endpoint}'),
            _buildDetailRow('Priority', _testCase.priority),
            _buildDetailRow('Category', _testCase.category),
            if (_testCase.actualStatusCode != null)
              _buildDetailRow(
                'HTTP Status',
                '${_testCase.actualStatusCode}',
                valueColor: _testCase.actualStatusCode == 200
                    ? Colors.green
                    : Colors.red,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.black87,
                fontWeight: valueColor != null ? FontWeight.bold : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationStepsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '✅ Verification Steps',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Expected results for each step:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const Divider(),
            ..._testCase.verifications.map((v) => _buildVerificationStep(v)),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationStep(TestCaseVerification verification) {
    final isVerified = verification.isVerified ?? false;
    final hasActual = verification.actualResult != null &&
        verification.actualResult!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isVerified
            ? Colors.green.shade50
            : (hasActual ? Colors.orange.shade50 : Colors.grey.shade50),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isVerified
              ? Colors.green.shade200
              : (hasActual ? Colors.orange.shade200 : Colors.grey.shade200),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isVerified ? Colors.green : Colors.grey.shade300,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    verification.step,
                    style: TextStyle(
                      color: isVerified ? Colors.white : Colors.black54,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  verification.action,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              if (isVerified)
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          _buildStepDetail('Expected', verification.expectedResult),
          if (hasActual) ...[
            const SizedBox(height: 4),
            _buildStepDetail(
              'Actual',
              verification.actualResult!,
              color: isVerified ? Colors.green : Colors.orange,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepDetail(String label, String value, {Color? color}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 12,
              color: color ?? Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: color ?? Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActualResultsCard() {
    if (_testCase.actualResults == null || _testCase.actualResults!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 Actual Results',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            ..._testCase.actualResults!.entries.map((entry) {
              return _buildDetailRow(
                entry.key,
                entry.value.toString(),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📝 Notes',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            if (_testCase.notes != null && _testCase.notes!.isNotEmpty)
              Text(_testCase.notes!)
            else
              const Text(
                'No notes available',
                style: TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
