/// Data redaction utilities for privacy-first LLM analysis.
///
/// This module ensures sensitive information is removed before
/// sending performance data to external LLM providers.

import '../models/performance_data.dart';

/// Privacy level for data redaction.
enum PrivacyLevel {
  /// Maximum privacy: Only aggregated metrics, no identifiers.
  maximum,

  /// Partial: Keep function/class names but redact file paths.
  partial,

  /// Minimal: Keep most identifiers, only redact obvious PII.
  minimal,
}

/// Handles redaction of performance data before LLM submission.
class DataRedactor {
  final PrivacyLevel level;

  const DataRedactor({this.level = PrivacyLevel.maximum});

  /// Redacts a performance snapshot based on privacy level.
  PerformanceSnapshot redact(PerformanceSnapshot snapshot) {
    return PerformanceSnapshot(
      timestamp: snapshot.timestamp,
      isolateId: _redactIsolateId(snapshot.isolateId),
      cpu: snapshot.cpu != null ? _redactCpu(snapshot.cpu!) : null,
      memory: snapshot.memory != null ? _redactMemory(snapshot.memory!) : null,
      timeline: snapshot.timeline?.redacted(),
    );
  }

  String _redactIsolateId(String id) {
    // Always anonymize isolate IDs
    return 'isolate_${id.hashCode.abs() % 1000}';
  }

  CpuData _redactCpu(CpuData data) {
    switch (level) {
      case PrivacyLevel.maximum:
        // At maximum privacy, keep user function names (from app code)
        // but anonymize internal Dart/Flutter function names
        return data.redactedSmartly();
      case PrivacyLevel.partial:
        return data.redacted(keepFunctionNames: true);
      case PrivacyLevel.minimal:
        return data;
    }
  }

  MemoryData _redactMemory(MemoryData data) {
    switch (level) {
      case PrivacyLevel.maximum:
        // At maximum privacy, keep user class names (they're what the user needs)
        // but anonymize internal/framework class names
        return data.redactedSmartly();
      case PrivacyLevel.partial:
        return data.redacted(keepClassNames: true);
      case PrivacyLevel.minimal:
        return data;
    }
  }

  /// Creates a summary suitable for LLM analysis.
  /// This is always heavily redacted for maximum privacy.
  Map<String, dynamic> createAnalysisSummary(PerformanceSnapshot snapshot) {
    final redacted = redact(snapshot);

    return {
      'timestamp': redacted.timestamp.toIso8601String(),
      'cpu': _createCpuSummary(redacted.cpu),
      'memory': _createMemorySummary(redacted.memory),
      'timeline': _createTimelineSummary(redacted.timeline),
    };
  }

  /// Creates an enhanced summary with retention paths and source locations.
  /// This gives the AI the exact root cause information for actionable insights.
  Map<String, dynamic> createEnhancedAnalysisSummary(PerformanceSnapshot snapshot) {
    final redacted = redact(snapshot);

    return {
      'timestamp': redacted.timestamp.toIso8601String(),
      'cpu': _createEnhancedCpuSummary(redacted.cpu),
      'memory': _createEnhancedMemorySummary(redacted.memory),
      'timeline': _createTimelineSummary(redacted.timeline),
    };
  }

  /// Enhanced memory summary that includes retention paths and source locations.
  Map<String, dynamic>? _createEnhancedMemorySummary(MemoryData? memory) {
    if (memory == null) return null;

    // Separate user classes (with enhanced data) from internal classes
    final userClasses = memory.topAllocations.where((a) => a.isUserClass).toList();
    final internalClasses = memory.topAllocations.where((a) => !a.isUserClass).take(5).toList();

    return {
      'heapUsedMB': (memory.usedHeapSize / (1024 * 1024)).toStringAsFixed(1),
      'heapCapacityMB': (memory.heapCapacity / (1024 * 1024)).toStringAsFixed(1),
      'heapUsagePercent': memory.heapUsagePercent.toStringAsFixed(1),
      'gcCount': memory.gcCount,
      // User/app classes with full context for root cause analysis
      'appClasses': userClasses.take(10).map((a) {
        return {
          'className': a.className,
          'instances': a.instanceCount,
          'bytesKB': (a.totalBytes / 1024).toStringAsFixed(1),
          'isUserClass': true,
          // Include source location if available
          if (a.sourceLocation != null) ...{
            'sourceLocation': a.sourceLocation!.displayPath,
            // Include actual code snippet for context-aware suggestions
            if (a.sourceLocation!.codeSnippet != null)
              'codeSnippet': a.sourceLocation!.codeSnippet,
            // Include usage context (where List<T> fields are defined in State class)
            if (a.sourceLocation!.usageContext != null)
              'usageContext': a.sourceLocation!.usageContext,
          },
          // Include retention path if available
          if (a.retentionInfo != null) ...{
            'retentionPath': a.retentionInfo!.pathSummary,
            'rootType': a.retentionInfo!.rootType,
          },
        };
      }).toList(),
      // Internal/framework classes for context
      'frameworkClasses': internalClasses.map((a) {
        return {
          'className': a.className,
          'instances': a.instanceCount,
          'bytesKB': (a.totalBytes / 1024).toStringAsFixed(1),
        };
      }).toList(),
    };
  }

  Map<String, dynamic>? _createCpuSummary(CpuData? cpu) {
    if (cpu == null) return null;

    return {
      'sampleCount': cpu.sampleCount,
      'totalCpuTimeMs': cpu.totalCpuTimeMs,
      'topFunctionsCount': cpu.topFunctions.length,
      'hotspots': cpu.topFunctions.take(5).map((f) {
        return {
          'name': f.functionName,
          'percentage': f.percentage.toStringAsFixed(1),
          'ticks': f.exclusiveTicks,
        };
      }).toList(),
    };
  }

  /// Enhanced CPU summary with source locations and code snippets.
  /// This enables app-specific jank suggestions.
  Map<String, dynamic>? _createEnhancedCpuSummary(CpuData? cpu) {
    if (cpu == null) return null;

    // Separate user functions from framework functions
    final userFunctions = cpu.topFunctions.where((f) => f.isUserFunction).toList();
    final frameworkFunctions = cpu.topFunctions.where((f) => !f.isUserFunction).take(5).toList();

    return {
      'sampleCount': cpu.sampleCount,
      'totalCpuTimeMs': cpu.totalCpuTimeMs,
      // User/app functions with source code for root cause analysis
      'appFunctions': userFunctions.take(10).map((f) {
        return {
          'functionName': f.functionName,
          if (f.className != null) 'className': f.className,
          'percentage': f.percentage.toStringAsFixed(1),
          'exclusiveTicks': f.exclusiveTicks,
          'isUserFunction': true,
          // Include source location if available
          if (f.sourceLocation != null) ...{
            'sourceLocation': f.sourceLocation!.displayPath,
            // Include actual code snippet for context-aware suggestions
            if (f.sourceLocation!.codeSnippet != null)
              'codeSnippet': f.sourceLocation!.codeSnippet,
          },
        };
      }).toList(),
      // Framework functions for context
      'frameworkFunctions': frameworkFunctions.map((f) {
        return {
          'functionName': f.functionName,
          if (f.className != null) 'className': f.className,
          'percentage': f.percentage.toStringAsFixed(1),
        };
      }).toList(),
    };
  }

  Map<String, dynamic>? _createMemorySummary(MemoryData? memory) {
    if (memory == null) return null;

    return {
      'heapUsedMB': (memory.usedHeapSize / (1024 * 1024)).toStringAsFixed(1),
      'heapCapacityMB': (memory.heapCapacity / (1024 * 1024)).toStringAsFixed(1),
      'heapUsagePercent': memory.heapUsagePercent.toStringAsFixed(1),
      'gcCount': memory.gcCount,
      'topAllocations': memory.topAllocations.take(5).map((a) {
        return {
          'type': a.className,
          'instances': a.instanceCount,
          'bytesKB': (a.totalBytes / 1024).toStringAsFixed(1),
        };
      }).toList(),
    };
  }

  Map<String, dynamic>? _createTimelineSummary(TimelineData? timeline) {
    if (timeline == null) return null;

    // Get jank frames for detailed analysis
    final jankFrames = timeline.frames.where((f) => f.isJank).take(10).toList();

    // Analyze jank pattern (build-heavy vs raster-heavy)
    int buildHeavy = 0;
    int rasterHeavy = 0;
    for (final frame in jankFrames) {
      if (frame.buildTimeMs > frame.rasterTimeMs) {
        buildHeavy++;
      } else {
        rasterHeavy++;
      }
    }

    // Group slow events by category for better analysis
    final slowEventsByCategory = <String, List<Map<String, dynamic>>>{};
    for (final event in timeline.slowEvents.take(20)) {
      slowEventsByCategory.putIfAbsent(event.category, () => []);
      slowEventsByCategory[event.category]!.add(event.toJson());
    }

    return {
      'totalFrames': timeline.totalFrames,
      'jankFrameCount': timeline.jankFrameCount,
      'jankPercent': timeline.jankPercent.toStringAsFixed(1),
      'avgFrameTimeMs': timeline.averageFrameTimeMs.toStringAsFixed(2),
      'p95FrameTimeMs': timeline.p95FrameTimeMs.toStringAsFixed(2),
      'p99FrameTimeMs': timeline.p99FrameTimeMs.toStringAsFixed(2),
      'jankPattern': buildHeavy > rasterHeavy ? 'build-heavy' : 'raster-heavy',
      'jankFrames': jankFrames.map((f) => {
        'totalTimeMs': f.totalTimeMs.toStringAsFixed(1),
        'buildTimeMs': f.buildTimeMs.toStringAsFixed(1),
        'rasterTimeMs': f.rasterTimeMs.toStringAsFixed(1),
        'cause': f.buildTimeMs > f.rasterTimeMs * 2
            ? 'Build phase (widget tree)'
            : f.rasterTimeMs > f.buildTimeMs * 2
                ? 'Raster phase (rendering)'
                : 'Mixed (both phases)',
      }).toList(),
      // NEW: Include slow operations that may be causing jank
      if (timeline.slowEvents.isNotEmpty) ...{
        'slowOperations': timeline.slowEvents.take(15).map((e) => e.toJson()).toList(),
        'slowOperationsByCategory': slowEventsByCategory,
      },
    };
  }
}

/// Patterns to detect and redact sensitive information.
class SensitivePatterns {
  static final emailPattern = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
  static final ipPattern = RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b');
  static final urlPattern = RegExp(r'https?://[^\s]+');
  static final pathPattern = RegExp(r'/[a-zA-Z0-9_/.-]+');
  static final tokenPattern = RegExp(r'(api[_-]?key|token|secret|password|auth)[=:][^\s]+', caseSensitive: false);

  /// Redact sensitive patterns from text.
  static String redactSensitive(String text) {
    var result = text;
    result = result.replaceAll(emailPattern, '[EMAIL]');
    result = result.replaceAll(ipPattern, '[IP]');
    result = result.replaceAll(tokenPattern, '[REDACTED]');
    result = result.replaceAll(urlPattern, '[URL]');
    // Be careful with paths - only redact absolute paths
    result = result.replaceAllMapped(
      RegExp(r'(/Users/|/home/|C:\\|/var/)[^\s:]+'),
      (m) => '[PATH]',
    );
    return result;
  }
}
