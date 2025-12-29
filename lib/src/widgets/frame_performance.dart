/// Frame performance visualization for UI jank detection.
///
/// Displays frame timing metrics, jank indicators, and helps identify
/// performance bottlenecks in the UI rendering pipeline.

import 'package:flutter/material.dart';
import '../models/performance_data.dart';

/// Callback when a jank frame is selected for analysis.
typedef OnJankFrameSelected = void Function(FrameTiming frame, int index);

/// Visual frame performance display showing jank metrics and frame timeline.
class FramePerformanceCard extends StatelessWidget {
  final TimelineData timeline;
  final CpuData? cpuData;
  final OnJankFrameSelected? onJankFrameSelected;

  const FramePerformanceCard({
    super.key,
    required this.timeline,
    this.cpuData,
    this.onJankFrameSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Frame Performance Overview (similar to Heap Usage)
        _buildPerformanceOverview(context),
        const SizedBox(height: 16),

        // Frame Timeline Visualization
        _buildFrameTimeline(context),
        const SizedBox(height: 16),

        // Jank Frames List (if any)
        if (timeline.jankFrameCount > 0) ...[
          _buildSectionHeader(context, 'Jank Frames', timeline.jankFrameCount),
          const SizedBox(height: 8),
          _buildJankFramesList(context),
          const SizedBox(height: 16),
        ],

        // CPU Hotspots (if available)
        if (cpuData != null && cpuData!.topFunctions.isNotEmpty) ...[
          _buildSectionHeader(context, 'CPU Hotspots', cpuData!.topFunctions.length),
          const SizedBox(height: 8),
          _buildCpuHotspots(context),
        ] else ...[
          // Show CPU profiling help when no data available
          _buildCpuProfilingHelp(context),
        ],
      ],
    );
  }

  /// Show help message when CPU profiling data is not available.
  Widget _buildCpuProfilingHelp(BuildContext context) {
    final hasUserFunctions = cpuData?.topFunctions.any((f) => f.isUserFunction) ?? false;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Colors.amber.shade700),
              const SizedBox(width: 8),
              Text(
                'CPU Profiling',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            cpuData == null
                ? 'No CPU profiling data available. For detailed jank root cause analysis:'
                : hasUserFunctions
                    ? 'No user function hotspots detected.'
                    : 'CPU samples collected but no user code detected. The app may be idle.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (cpuData == null) ...[
            const SizedBox(height: 8),
            _buildHelpStep(context, '1', 'Run your app in profile mode:', 'flutter run --profile'),
            _buildHelpStep(context, '2', 'Interact with your app to generate activity', null),
            _buildHelpStep(context, '3', 'Click "Get AI Analysis" while the app is doing work', null),
          ] else if (!hasUserFunctions) ...[
            const SizedBox(height: 8),
            _buildHelpStep(context, '•', 'Interact with your app (scroll, tap, navigate)', null),
            _buildHelpStep(context, '•', 'Click "Refresh" to collect new samples', null),
          ],
        ],
      ),
    );
  }

  Widget _buildHelpStep(BuildContext context, String number, String text, String? code) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Text(
              number,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.amber.shade700,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: Theme.of(context).textTheme.bodySmall),
                if (code != null)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      code,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceOverview(BuildContext context) {
    final jankPercent = timeline.jankPercent;
    final isHealthy = jankPercent < 5;
    final isWarning = jankPercent >= 5 && jankPercent < 15;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isHealthy
                        ? Icons.check_circle
                        : isWarning
                            ? Icons.warning
                            : Icons.error,
                    size: 18,
                    color: _getJankColor(jankPercent),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Frame Performance',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
              Text(
                '${timeline.jankFrameCount} / ${timeline.totalFrames} jank',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _getJankColor(jankPercent),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Jank percentage bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: jankPercent / 100,
              minHeight: 8,
              backgroundColor: Theme.of(context).colorScheme.surface,
              valueColor: AlwaysStoppedAnimation(_getJankColor(jankPercent)),
            ),
          ),
          const SizedBox(height: 8),
          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${jankPercent.toStringAsFixed(1)}% jank rate',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _getJankColor(jankPercent),
                      fontWeight: FontWeight.w500,
                    ),
              ),
              Row(
                children: [
                  _buildMiniStat(context, 'Avg', '${timeline.averageFrameTimeMs.toStringAsFixed(1)}ms'),
                  const SizedBox(width: 12),
                  _buildMiniStat(context, 'P95', '${timeline.p95FrameTimeMs.toStringAsFixed(1)}ms'),
                  const SizedBox(width: 12),
                  _buildMiniStat(context, 'P99', '${timeline.p99FrameTimeMs.toStringAsFixed(1)}ms'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(BuildContext context, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  Widget _buildFrameTimeline(BuildContext context) {
    final frames = timeline.frames.take(50).toList();
    if (frames.isEmpty) return const SizedBox.shrink();

    const targetFrameTime = 16.67; // 60fps target

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Frames',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            Text(
              '16.67ms target (60fps)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 60,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: frames.asMap().entries.map((entry) {
              final index = entry.key;
              final frame = entry.value;
              final heightRatio = (frame.totalTimeMs / 50).clamp(0.1, 1.0);

              return Expanded(
                child: GestureDetector(
                  onTap: frame.isJank
                      ? () => onJankFrameSelected?.call(frame, index)
                      : null,
                  child: Tooltip(
                    message: 'Frame ${index + 1}\n'
                        'Total: ${frame.totalTimeMs.toStringAsFixed(1)}ms\n'
                        'Build: ${frame.buildTimeMs.toStringAsFixed(1)}ms\n'
                        'Raster: ${frame.rasterTimeMs.toStringAsFixed(1)}ms',
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 0.5),
                      decoration: BoxDecoration(
                        color: frame.isJank
                            ? Colors.red.withOpacity(0.8)
                            : Colors.green.withOpacity(0.6),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                      ),
                      height: 60 * heightRatio,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // Target line indicator
        Container(
          height: 1,
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: title == 'Jank Frames'
                ? Colors.red.withOpacity(0.2)
                : Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            count.toString(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: title == 'Jank Frames'
                      ? Colors.red
                      : Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildJankFramesList(BuildContext context) {
    final jankFrames = timeline.frames.where((f) => f.isJank).take(10).toList();

    return Column(
      children: jankFrames.asMap().entries.map((entry) {
        final index = entry.key;
        final frame = entry.value;
        final severity = _getFrameSeverity(frame.totalTimeMs);

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.05),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.red.withOpacity(0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: severity == 'critical'
                      ? Colors.red
                      : severity == 'high'
                          ? Colors.orange
                          : Colors.yellow.shade700,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${frame.totalTimeMs.toStringAsFixed(1)}ms total',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'Build: ${frame.buildTimeMs.toStringAsFixed(1)}ms | Raster: ${frame.rasterTimeMs.toStringAsFixed(1)}ms',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getSeverityColor(severity).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _getJankCause(frame),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _getSeverityColor(severity),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCpuHotspots(BuildContext context) {
    final hotspots = cpuData!.topFunctions.take(5).toList();

    return Column(
      children: hotspots.map((func) {
        final isUserFunc = func.isUserFunction;
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isUserFunc
                ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 50,
                child: Text(
                  '${func.percentage.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isUserFunc
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      func.functionName,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: isUserFunc ? FontWeight.w600 : FontWeight.normal,
                        color: isUserFunc ? null : Theme.of(context).colorScheme.outline,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (func.className != null)
                      Text(
                        func.className!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                              fontSize: 10,
                            ),
                      ),
                  ],
                ),
              ),
              if (isUserFunc)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'App',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _getJankColor(double jankPercent) {
    if (jankPercent < 5) return Colors.green;
    if (jankPercent < 15) return Colors.orange;
    return Colors.red;
  }

  String _getFrameSeverity(double totalTimeMs) {
    if (totalTimeMs > 50) return 'critical';
    if (totalTimeMs > 33) return 'high';
    return 'medium';
  }

  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'critical':
        return Colors.red;
      case 'high':
        return Colors.orange;
      default:
        return Colors.yellow.shade700;
    }
  }

  String _getJankCause(FrameTiming frame) {
    if (frame.buildTimeMs > frame.rasterTimeMs * 2) {
      return 'Build heavy';
    } else if (frame.rasterTimeMs > frame.buildTimeMs * 2) {
      return 'Raster heavy';
    }
    return 'Mixed';
  }
}
