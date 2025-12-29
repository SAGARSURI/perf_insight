/// Metric visualization widgets for performance data.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/performance_data.dart';

/// Displays performance metrics as charts and cards.
class MetricCharts extends StatelessWidget {
  final PerformanceSnapshot snapshot;

  const MetricCharts({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(context, 'CPU Profile', Icons.speed),
          const SizedBox(height: 8),
          if (snapshot.cpu != null)
            CpuMetricCard(cpu: snapshot.cpu!)
          else
            _buildNoDataCard(context, 'No CPU data available'),
          const SizedBox(height: 16),
          _buildSectionTitle(context, 'Memory Usage', Icons.memory),
          const SizedBox(height: 8),
          if (snapshot.memory != null)
            MemoryMetricCard(memory: snapshot.memory!)
          else
            _buildNoDataCard(context, 'No memory data available'),
          const SizedBox(height: 16),
          _buildSectionTitle(context, 'Frame Timing', Icons.timer),
          const SizedBox(height: 8),
          if (snapshot.timeline != null)
            TimelineMetricCard(timeline: snapshot.timeline!)
          else
            _buildNoDataCard(context, 'No timeline data available'),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  Widget _buildNoDataCard(BuildContext context, String message) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ),
      ),
    );
  }
}

/// Card displaying CPU profiling metrics.
class CpuMetricCard extends StatelessWidget {
  final CpuData cpu;

  const CpuMetricCard({super.key, required this.cpu});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMetric(context, 'Samples', cpu.sampleCount.toString()),
                _buildMetric(context, 'CPU Time',
                    '${cpu.totalCpuTimeMs.toStringAsFixed(1)}ms'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Top Functions',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            if (cpu.topFunctions.isEmpty)
              Text(
                'No hot functions detected',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              ...cpu.topFunctions.take(5).map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _buildFunctionRow(context, f),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  Widget _buildFunctionRow(BuildContext context, FunctionSample f) {
    return Row(
      children: [
        Expanded(
          child: Text(
            f.functionName,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Container(
          width: 50,
          alignment: Alignment.centerRight,
          child: Text(
            '${f.percentage.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: f.percentage > 20
                  ? Colors.red
                  : f.percentage > 10
                      ? Colors.orange
                      : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// Card displaying memory metrics.
class MemoryMetricCard extends StatelessWidget {
  final MemoryData memory;

  const MemoryMetricCard({super.key, required this.memory});

  List<AllocationSample> get _userClasses =>
      memory.topAllocations.where((a) => a.isUserClass).toList();

  List<AllocationSample> get _internalClasses =>
      memory.topAllocations.where((a) => !a.isUserClass).toList();

  @override
  Widget build(BuildContext context) {
    final usedMB = memory.usedHeapSize / (1024 * 1024);
    final capacityMB = memory.heapCapacity / (1024 * 1024);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Heap Usage',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                      Text(
                        '${usedMB.toStringAsFixed(1)} / ${capacityMB.toStringAsFixed(1)} MB',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 60,
                  height: 60,
                  child: _buildUsageGauge(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: memory.heapUsagePercent / 100,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(_getUsageColor()),
            ),
            const SizedBox(height: 12),
            // Show user classes first (app-specific)
            if (_userClasses.isNotEmpty) ...[
              Text(
                'App Classes',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              const SizedBox(height: 8),
              ..._userClasses.take(5).map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _buildAllocationRow(context, a, isUserClass: true),
                  )),
              const SizedBox(height: 12),
            ],
            Text(
              'Top Allocations',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            if (memory.topAllocations.isEmpty)
              Text(
                'No significant allocations',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              ..._internalClasses.take(5).map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _buildAllocationRow(context, a, isUserClass: false),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageGauge(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 50,
          height: 50,
          child: CircularProgressIndicator(
            value: memory.heapUsagePercent / 100,
            strokeWidth: 6,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(_getUsageColor()),
          ),
        ),
        Text(
          '${memory.heapUsagePercent.toStringAsFixed(0)}%',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Color _getUsageColor() {
    if (memory.heapUsagePercent > 80) return Colors.red;
    if (memory.heapUsagePercent > 60) return Colors.orange;
    return Colors.green;
  }

  Widget _buildAllocationRow(BuildContext context, AllocationSample a,
      {bool isUserClass = false}) {
    final sizeKB = a.totalBytes / 1024;
    return Row(
      children: [
        if (isUserClass)
          Container(
            width: 4,
            height: 16,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        Expanded(
          child: Text(
            a.className,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: isUserClass ? FontWeight.w600 : FontWeight.normal,
              color: isUserClass
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '${a.instanceCount}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 60,
          alignment: Alignment.centerRight,
          child: Text(
            '${sizeKB.toStringAsFixed(1)} KB',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// Card displaying timeline/frame timing metrics.
class TimelineMetricCard extends StatelessWidget {
  final TimelineData timeline;

  const TimelineMetricCard({super.key, required this.timeline});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMetric(
                    context, 'Frames', timeline.totalFrames.toString()),
                _buildMetric(context, 'Jank',
                    '${timeline.jankPercent.toStringAsFixed(1)}%'),
                _buildMetric(context, 'Avg',
                    '${timeline.averageFrameTimeMs.toStringAsFixed(1)}ms'),
                _buildMetric(context, 'P95',
                    '${timeline.p95FrameTimeMs.toStringAsFixed(1)}ms'),
              ],
            ),
            const SizedBox(height: 12),
            if (timeline.frames.length > 1) _buildFrameChart(context),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 10,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  Widget _buildFrameChart(BuildContext context) {
    final frames = timeline.frames.take(30).toList();

    return SizedBox(
      height: 60,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 33.33, // 30fps threshold
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 16.67, // 60fps line
            getDrawingHorizontalLine: (value) => FlLine(
              color: value == 16.67
                  ? Colors.green.withOpacity(0.5)
                  : Colors.transparent,
              strokeWidth: 1,
              dashArray: [5, 5],
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          barGroups: frames.asMap().entries.map((entry) {
            final frame = entry.value;
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: frame.totalTimeMs.clamp(0, 33.33),
                  color: frame.isJank ? Colors.red : Colors.green,
                  width: 4,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(2),
                    topRight: Radius.circular(2),
                  ),
                ),
              ],
            );
          }).toList(),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final frame = frames[group.x];
                return BarTooltipItem(
                  '${frame.totalTimeMs.toStringAsFixed(1)}ms',
                  const TextStyle(color: Colors.white, fontSize: 10),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
