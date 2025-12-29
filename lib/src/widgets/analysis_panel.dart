/// Analysis panel widget for displaying LLM analysis results.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/analysis_result.dart';

/// Panel displaying the LLM analysis results.
class AnalysisPanel extends StatelessWidget {
  final AnalysisResult result;
  final String? debugInfo;

  const AnalysisPanel({super.key, required this.result, this.debugInfo});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 16),
          // Debug info section
          if (debugInfo != null) ...[
            _buildDebugSection(context),
            const SizedBox(height: 16),
          ],
          _buildSummary(context),
          const SizedBox(height: 24),
          _buildIssuesSection(context),
          const SizedBox(height: 24),
          _buildRecommendationsSection(context),
          const SizedBox(height: 16),
          _buildMetadata(context),
        ],
      ),
    );
  }

  Widget _buildDebugSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.yellow.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Text(
                'DEBUG: Data Sent to AI',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            debugInfo!,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.insights,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          'Performance Analysis',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Spacer(),
        Chip(
          avatar: Icon(
            _getProviderIcon(),
            size: 16,
          ),
          label: Text('${result.provider} • ${result.model}'),
        ),
      ],
    );
  }

  IconData _getProviderIcon() {
    return result.provider.toLowerCase() == 'claude'
        ? Icons.smart_toy
        : Icons.psychology;
  }

  Widget _buildSummary(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.summarize,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Summary',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            result.summary,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildIssuesSection(BuildContext context) {
    if (result.issues.isEmpty) {
      return _buildNoIssuesCard(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.warning_amber,
              color: result.hasCriticalIssues
                  ? Colors.red
                  : result.hasHighIssues
                      ? Colors.orange
                      : Colors.yellow.shade700,
            ),
            const SizedBox(width: 8),
            Text(
              'Issues Found (${result.issues.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...result.sortedIssues.map((issue) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: IssueCard(issue: issue),
            )),
      ],
    );
  }

  Widget _buildNoIssuesCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No significant performance issues detected!',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationsSection(BuildContext context) {
    if (result.recommendations.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.lightbulb,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 8),
            Text(
              'Recommendations',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...result.recommendations.map((rec) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(fontSize: 16)),
                  Expanded(child: Text(rec)),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildMetadata(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Analyzed at ${_formatTime(result.timestamp)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          Text(
            'Response time: ${result.metrics.responseTime.inMilliseconds}ms',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}

/// Card displaying a single performance issue.
class IssueCard extends StatelessWidget {
  final PerformanceIssue issue;

  const IssueCard({super.key, required this.issue});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _getSeverityColor().withOpacity(0.5),
        ),
      ),
      child: ExpansionTile(
        leading: _buildSeverityIcon(),
        title: Text(
          issue.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Row(
          children: [
            _buildChip(issue.severity.displayName, _getSeverityColor()),
            const SizedBox(width: 4),
            _buildChip(issue.category.displayName, Colors.blue),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(issue.description),
                if (issue.suggestedFixes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Suggested Fixes:',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ...issue.suggestedFixes.map((fix) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.arrow_right, size: 20),
                            Expanded(child: Text(fix)),
                          ],
                        ),
                      )),
                ],
                if (issue.codeExample != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Example:',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _buildCodeBlock(context, issue.codeExample!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityIcon() {
    IconData icon;
    switch (issue.severity) {
      case IssueSeverity.critical:
        icon = Icons.error;
        break;
      case IssueSeverity.high:
        icon = Icons.warning;
        break;
      case IssueSeverity.medium:
        icon = Icons.info;
        break;
      case IssueSeverity.low:
        icon = Icons.lightbulb_outline;
        break;
      case IssueSeverity.info:
        icon = Icons.help_outline;
        break;
    }
    return Icon(icon, color: _getSeverityColor());
  }

  Color _getSeverityColor() {
    switch (issue.severity) {
      case IssueSeverity.critical:
        return Colors.red;
      case IssueSeverity.high:
        return Colors.orange;
      case IssueSeverity.medium:
        return Colors.yellow.shade700;
      case IssueSeverity.low:
        return Colors.blue;
      case IssueSeverity.info:
        return Colors.grey;
    }
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildCodeBlock(BuildContext context, String code) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          SelectableText(
            code,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copied to clipboard')),
                );
              },
              tooltip: 'Copy code',
            ),
          ),
        ],
      ),
    );
  }
}
