/// Visualization of object retention paths.
///
/// Shows WHY objects can't be garbage collected by displaying
/// the chain from object → field → parent → ... → GC root.

import 'package:flutter/material.dart';
import '../models/performance_data.dart';

/// Displays a retention path as a visual chain.
class RetentionPathView extends StatelessWidget {
  final RetentionInfo retentionInfo;
  final bool compact;

  const RetentionPathView({
    super.key,
    required this.retentionInfo,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompactView(context);
    }
    return _buildFullView(context);
  }

  Widget _buildCompactView(BuildContext context) {
    // Show simplified path: ClassName → field → ParentClass → ... → GC Root
    final summary = retentionInfo.pathSummary;
    if (summary.isEmpty) {
      return Text(
        'Retention path unavailable',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
      );
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (int i = 0; i < summary.length && i < 5; i++) ...[
          if (i > 0)
            Icon(
              Icons.arrow_forward,
              size: 12,
              color: Theme.of(context).colorScheme.outline,
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: i == summary.length - 1
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              summary[i],
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: i == summary.length - 1
                    ? Theme.of(context).colorScheme.onErrorContainer
                    : null,
              ),
            ),
          ),
        ],
        if (summary.length > 5)
          Text(
            '... → ${retentionInfo.rootType}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
      ],
    );
  }

  Widget _buildFullView(BuildContext context) {
    if (retentionInfo.path.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 16,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Text(
              'Retention path unavailable',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.link,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Why it\'s retained',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  retentionInfo.rootType,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Retention chain
          ...retentionInfo.path.asMap().entries.map((entry) {
            final index = entry.key;
            final step = entry.value;
            final isLast = index == retentionInfo.path.length - 1;

            return _RetentionStepWidget(
              step: step,
              isFirst: index == 0,
              isLast: isLast,
            );
          }),
        ],
      ),
    );
  }
}

/// Single step in the retention path visualization.
class _RetentionStepWidget extends StatelessWidget {
  final RetentionStep step;
  final bool isFirst;
  final bool isLast;

  const _RetentionStepWidget({
    required this.step,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Connector line
          SizedBox(
            width: 24,
            child: Column(
              children: [
                if (!isFirst)
                  Container(
                    width: 2,
                    height: 8,
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                  ),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: step.isGcRoot
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 2,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Step content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Class/description
                  Text(
                    step.className ?? step.description,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: step.isGcRoot ? FontWeight.bold : FontWeight.w500,
                      color: step.isGcRoot
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),

                  // Field name (if present)
                  if (step.fieldName != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.subdirectory_arrow_right,
                          size: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'via field: ${step.fieldName}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Source location (if present)
                  if (step.sourceLocation != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      step.sourceLocation!.displayPath,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple one-line retention summary.
class RetentionSummary extends StatelessWidget {
  final RetentionInfo? retentionInfo;

  const RetentionSummary({super.key, this.retentionInfo});

  @override
  Widget build(BuildContext context) {
    if (retentionInfo == null) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        Icon(
          Icons.link,
          size: 12,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            retentionInfo!.pathSummary.take(3).join(' → '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                  fontSize: 10,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
