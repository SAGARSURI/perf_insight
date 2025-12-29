/// Visual treemap for memory allocation visualization.
///
/// Displays memory usage as proportionally-sized tiles that users can
/// click to drill down into specific class details.

import 'package:flutter/material.dart';
import '../models/performance_data.dart';

/// Callback when a class is selected in the treemap.
typedef OnClassSelected = void Function(AllocationSample allocation);

/// Visual memory treemap showing allocation sizes as proportional tiles.
class MemoryTreemap extends StatelessWidget {
  final MemoryData memory;
  final OnClassSelected? onClassSelected;
  final AllocationSample? selectedClass;

  const MemoryTreemap({
    super.key,
    required this.memory,
    this.onClassSelected,
    this.selectedClass,
  });

  @override
  Widget build(BuildContext context) {
    final userClasses = memory.topAllocations.where((a) => a.isUserClass).toList();
    final internalClasses = memory.topAllocations.where((a) => !a.isUserClass).toList();

    // Calculate total bytes for proportions
    final totalBytes = memory.topAllocations.fold<int>(
      0,
      (sum, a) => sum + a.totalBytes,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Heap overview bar
        _buildHeapOverview(context),
        const SizedBox(height: 16),

        // Section: App Classes (treemap)
        if (userClasses.isNotEmpty) ...[
          _buildSectionHeader(context, 'App Classes', userClasses.length),
          const SizedBox(height: 8),
          _buildTreemap(context, userClasses, totalBytes, isUserClass: true),
          const SizedBox(height: 16),
        ],

        // Section: Framework/Internal Classes (list)
        if (internalClasses.isNotEmpty) ...[
          _buildSectionHeader(context, 'Framework Classes', internalClasses.length),
          const SizedBox(height: 8),
          _buildClassList(context, internalClasses.take(10).toList()),
        ],
      ],
    );
  }

  Widget _buildHeapOverview(BuildContext context) {
    final usedMB = memory.heapUsedMB;
    final capacityMB = memory.heapCapacityMB;
    final percent = memory.percentUsed;

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
              Text(
                'Heap Usage',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              Text(
                '${usedMB.toStringAsFixed(1)} / ${capacityMB.toStringAsFixed(1)} MB',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 8,
              backgroundColor: Theme.of(context).colorScheme.surface,
              valueColor: AlwaysStoppedAnimation(_getUsageColor(percent)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${percent.toStringAsFixed(1)}% used',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
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
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            count.toString(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildTreemap(
    BuildContext context,
    List<AllocationSample> allocations,
    int totalBytes, {
    bool isUserClass = false,
  }) {
    if (allocations.isEmpty) {
      return const SizedBox.shrink();
    }

    // Calculate proportions and layout
    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: allocations.map((allocation) {
            // Calculate tile size based on proportion of total memory
            final proportion = totalBytes > 0 ? allocation.totalBytes / totalBytes : 0.0;
            // Minimum 140px to fit class names, max based on proportion
            final minWidth = 140.0;
            final maxWidth = constraints.maxWidth * 0.45;
            final width = (constraints.maxWidth * proportion * 3)
                .clamp(minWidth, maxWidth);

            final isSelected = selectedClass?.className == allocation.className;

            return _MemoryTile(
              allocation: allocation,
              width: width,
              isUserClass: isUserClass,
              isSelected: isSelected,
              onTap: () => onClassSelected?.call(allocation),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildClassList(BuildContext context, List<AllocationSample> allocations) {
    return Column(
      children: allocations.map((allocation) {
        final sizeKB = allocation.totalBytes / 1024;
        final isSelected = selectedClass?.className == allocation.className;

        return InkWell(
          onTap: () => onClassSelected?.call(allocation),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
                  : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    allocation.className,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${allocation.instanceCount}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 60,
                  child: Text(
                    '${sizeKB.toStringAsFixed(1)} KB',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Color _getUsageColor(double percent) {
    if (percent > 80) return Colors.red;
    if (percent > 60) return Colors.orange;
    return Colors.green;
  }
}

/// Individual memory tile in the treemap.
class _MemoryTile extends StatelessWidget {
  final AllocationSample allocation;
  final double width;
  final bool isUserClass;
  final bool isSelected;
  final VoidCallback onTap;

  const _MemoryTile({
    required this.allocation,
    required this.width,
    required this.isUserClass,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sizeKB = allocation.totalBytes / 1024;
    final color = isUserClass
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.secondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: width,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withOpacity(0.2)
                : color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? color : color.withOpacity(0.3),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Tooltip(
            message: '${allocation.className}\n${sizeKB.toStringAsFixed(1)} KB (${allocation.instanceCount} instances)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  allocation.className,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? color : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${sizeKB.toStringAsFixed(1)} KB',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '(${allocation.instanceCount})',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                if (allocation.sourceLocation != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    allocation.sourceLocation!.displayPath,
                    style: TextStyle(
                      fontSize: 9,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
