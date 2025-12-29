/// Performance data models for CPU, Memory, and Timeline metrics.
/// These models are designed with privacy-first redaction built in.
///
/// Note: CpuProfilingStatus is defined in cpu_collector.dart and re-exported
/// from performance_collector.dart for backwards compatibility.

// ============================================================================
// SOURCE LOCATION & RETENTION PATH MODELS
// ============================================================================

/// Represents a source code location (file:line).
/// Named CodeLocation to avoid conflict with vm_service.SourceLocation.
class CodeLocation {
  final String filePath;
  final int? lineNumber; // null means line number couldn't be determined
  final String? functionName;
  final String? className;
  final String? codeSnippet; // Actual source code around this location
  final String? usageContext; // Where this class is used (e.g., State class with List<T> fields)

  CodeLocation({
    required this.filePath,
    this.lineNumber,
    this.functionName,
    this.className,
    this.codeSnippet,
    this.usageContext,
  });

  /// Returns a user-friendly display string (e.g., "lib/main.dart:140" or "lib/main.dart")
  String get displayPath {
    // Simplify path - remove package prefix if present
    var path = filePath;
    if (path.startsWith('package:')) {
      final parts = path.split('/');
      if (parts.length > 1) {
        path = parts.sublist(1).join('/');
      }
    }
    // Only include line number if we know it
    if (lineNumber != null && lineNumber! > 0) {
      return '$path:$lineNumber';
    }
    return path;
  }

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        if (lineNumber != null) 'lineNumber': lineNumber,
        if (functionName != null) 'functionName': functionName,
        if (className != null) 'className': className,
        if (codeSnippet != null) 'codeSnippet': codeSnippet,
        if (usageContext != null) 'usageContext': usageContext,
      };
}

/// A single step in an object's retention path.
class RetentionStep {
  final String description;
  final String? fieldName;
  final String? className;
  final CodeLocation? sourceLocation;
  final bool isGcRoot;

  RetentionStep({
    required this.description,
    this.fieldName,
    this.className,
    this.sourceLocation,
    this.isGcRoot = false,
  });

  Map<String, dynamic> toJson() => {
        'description': description,
        if (fieldName != null) 'fieldName': fieldName,
        if (className != null) 'className': className,
        if (sourceLocation != null) 'sourceLocation': sourceLocation!.toJson(),
        'isGcRoot': isGcRoot,
      };
}

/// Full retention path showing WHY an object can't be garbage collected.
class RetentionInfo {
  final String className;
  final List<RetentionStep> path;
  final String rootType; // "static field", "global", "widget tree", "isolate"

  RetentionInfo({
    required this.className,
    required this.path,
    required this.rootType,
  });

  /// Returns a simple list of field names in the path.
  List<String> get pathSummary =>
      path.map((s) => s.fieldName ?? s.description).toList();

  Map<String, dynamic> toJson() => {
        'className': className,
        'rootType': rootType,
        'path': path.map((s) => s.toJson()).toList(),
        'pathSummary': pathSummary,
      };
}

/// Represents where objects of a class are being allocated.
class AllocationSite {
  final CodeLocation location;
  final int allocationCount;
  final String? stackTrace;

  AllocationSite({
    required this.location,
    required this.allocationCount,
    this.stackTrace,
  });

  Map<String, dynamic> toJson() => {
        'location': location.toJson(),
        'allocationCount': allocationCount,
        if (stackTrace != null) 'stackTrace': stackTrace,
      };
}

// ============================================================================
// PERFORMANCE SNAPSHOT MODELS
// ============================================================================

/// Represents a snapshot of all performance data at a point in time.
class PerformanceSnapshot {
  final DateTime timestamp;
  final CpuData? cpu;
  final MemoryData? memory;
  final TimelineData? timeline;
  final String isolateId;

  PerformanceSnapshot({
    required this.timestamp,
    required this.isolateId,
    this.cpu,
    this.memory,
    this.timeline,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'isolateId': isolateId,
        if (cpu != null) 'cpu': cpu!.toJson(),
        if (memory != null) 'memory': memory!.toJson(),
        if (timeline != null) 'timeline': timeline!.toJson(),
      };
}

/// CPU profiling data with redaction support.
class CpuData {
  final int sampleCount;
  final int samplePeriodMicros;
  final int maxStackDepth;
  final List<FunctionSample> topFunctions;
  final double totalCpuTimeMs;

  CpuData({
    required this.sampleCount,
    required this.samplePeriodMicros,
    required this.maxStackDepth,
    required this.topFunctions,
    required this.totalCpuTimeMs,
  });

  /// Returns a redacted version suitable for LLM analysis.
  CpuData redacted({bool keepFunctionNames = false}) {
    return CpuData(
      sampleCount: sampleCount,
      samplePeriodMicros: samplePeriodMicros,
      maxStackDepth: maxStackDepth,
      totalCpuTimeMs: totalCpuTimeMs,
      topFunctions: topFunctions
          .map((f) => f.redacted(keepFunctionNames: keepFunctionNames))
          .toList(),
    );
  }

  /// Smart redaction: keeps user function names, redacts internal function names.
  CpuData redactedSmartly() {
    return CpuData(
      sampleCount: sampleCount,
      samplePeriodMicros: samplePeriodMicros,
      maxStackDepth: maxStackDepth,
      totalCpuTimeMs: totalCpuTimeMs,
      topFunctions: topFunctions.map((f) {
        return f.redacted(keepFunctionNames: f.isUserFunction);
      }).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'sampleCount': sampleCount,
        'samplePeriodMicros': samplePeriodMicros,
        'maxStackDepth': maxStackDepth,
        'totalCpuTimeMs': totalCpuTimeMs,
        'topFunctions': topFunctions.map((f) => f.toJson()).toList(),
      };
}

/// Represents a function sample from CPU profiling.
class FunctionSample {
  final String functionName;
  final String? className;
  final String? libraryUri;
  final int exclusiveTicks;
  final int inclusiveTicks;
  final double percentage;
  final CodeLocation? sourceLocation; // Source code location and snippet
  final String? functionId; // VM function ID for fetching source

  FunctionSample({
    required this.functionName,
    this.className,
    this.libraryUri,
    required this.exclusiveTicks,
    required this.inclusiveTicks,
    required this.percentage,
    this.sourceLocation,
    this.functionId,
  });

  /// Create a copy with updated fields
  FunctionSample copyWith({
    CodeLocation? sourceLocation,
  }) {
    return FunctionSample(
      functionName: functionName,
      className: className,
      libraryUri: libraryUri,
      exclusiveTicks: exclusiveTicks,
      inclusiveTicks: inclusiveTicks,
      percentage: percentage,
      sourceLocation: sourceLocation ?? this.sourceLocation,
      functionId: functionId,
    );
  }

  /// Check if this is a user/app function (not internal Dart/Flutter)
  bool get isUserFunction {
    // Must have a library URI
    if (libraryUri == null) return false;

    // Exclude dart: core libraries
    if (libraryUri!.startsWith('dart:')) return false;

    // Exclude Flutter framework
    if (libraryUri!.contains('package:flutter/')) return false;

    // Exclude common Flutter plugins (but not all packages)
    if (libraryUri!.contains('package:devtools')) return false;
    if (libraryUri!.contains('package:vm_service')) return false;

    // Include anything from a package (user's packages)
    if (libraryUri!.startsWith('package:')) {
      // Exclude more Flutter ecosystem packages
      if (libraryUri!.contains('package:flutter_')) return false;
      if (libraryUri!.contains('package:cupertino_')) return false;
      return true;
    }

    // Also include file:// URIs (local development files)
    if (libraryUri!.startsWith('file://')) return true;

    return false;
  }

  /// Returns a redacted version with optional function name preservation.
  FunctionSample redacted({bool keepFunctionNames = false}) {
    return FunctionSample(
      functionName: keepFunctionNames ? functionName : 'function_${hashCode.abs() % 1000}',
      className: keepFunctionNames ? className : (className != null ? 'Class_${className.hashCode.abs() % 100}' : null),
      libraryUri: null, // Always redact file paths
      exclusiveTicks: exclusiveTicks,
      inclusiveTicks: inclusiveTicks,
      percentage: percentage,
      sourceLocation: keepFunctionNames ? sourceLocation : null,
      functionId: null,
    );
  }

  Map<String, dynamic> toJson() => {
        'functionName': functionName,
        if (className != null) 'className': className,
        if (libraryUri != null) 'libraryUri': libraryUri,
        'exclusiveTicks': exclusiveTicks,
        'inclusiveTicks': inclusiveTicks,
        'percentage': percentage,
        if (sourceLocation != null) 'sourceLocation': sourceLocation!.toJson(),
      };
}

/// Memory usage data with allocation information.
class MemoryData {
  final int usedHeapSize;
  final int heapCapacity;
  final int externalUsage;
  final List<AllocationSample> topAllocations;
  final int gcCount;

  MemoryData({
    required this.usedHeapSize,
    required this.heapCapacity,
    required this.externalUsage,
    required this.topAllocations,
    required this.gcCount,
  });

  double get heapUsagePercent => heapCapacity > 0 ? (usedHeapSize / heapCapacity) * 100 : 0;
  double get heapUsedMB => usedHeapSize / (1024 * 1024);
  double get heapCapacityMB => heapCapacity / (1024 * 1024);
  double get percentUsed => heapUsagePercent;

  /// Returns a redacted version suitable for LLM analysis.
  MemoryData redacted({bool keepClassNames = false}) {
    return MemoryData(
      usedHeapSize: usedHeapSize,
      heapCapacity: heapCapacity,
      externalUsage: externalUsage,
      gcCount: gcCount,
      topAllocations: topAllocations
          .map((a) => a.redacted(keepClassName: keepClassNames))
          .toList(),
    );
  }

  /// Smart redaction: keeps user class names, redacts internal class names.
  /// This is ideal for LLM analysis - the AI can see app-specific classes
  /// while internal Dart/Flutter classes are anonymized.
  MemoryData redactedSmartly() {
    return MemoryData(
      usedHeapSize: usedHeapSize,
      heapCapacity: heapCapacity,
      externalUsage: externalUsage,
      gcCount: gcCount,
      topAllocations: topAllocations.map((a) {
        // Keep user class names, redact internal class names
        return a.redacted(keepClassName: a.isUserClass);
      }).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'usedHeapSizeBytes': usedHeapSize,
        'heapCapacityBytes': heapCapacity,
        'heapUsagePercent': heapUsagePercent.toStringAsFixed(1),
        'externalUsageBytes': externalUsage,
        'gcCount': gcCount,
        'topAllocations': topAllocations.map((a) => a.toJson()).toList(),
      };
}

/// Represents a class allocation sample with optional deep analysis data.
class AllocationSample {
  final String className;
  final String? libraryUri;
  final int instanceCount;
  final int totalBytes;
  final int accumulatedBytes;

  // Enhanced analysis data (populated on demand)
  final CodeLocation? sourceLocation;
  final RetentionInfo? retentionInfo;
  final List<AllocationSite>? allocationSites;
  final String? classId; // VM Service class ID for drill-down

  // Cached isUserClass value (survives redaction when libraryUri is nulled)
  final bool? _isUserClassCached;

  AllocationSample({
    required this.className,
    this.libraryUri,
    required this.instanceCount,
    required this.totalBytes,
    required this.accumulatedBytes,
    this.sourceLocation,
    this.retentionInfo,
    this.allocationSites,
    this.classId,
    bool? isUserClassCached,
  }) : _isUserClassCached = isUserClassCached;

  /// Check if this is a user/app class (not internal Dart/Flutter)
  bool get isUserClass {
    // Use cached value if available (survives redaction)
    if (_isUserClassCached != null) return _isUserClassCached;

    // Filter out internal classes (start with _)
    if (className.startsWith('_')) return false;

    // Must have a library URI to be considered a user class
    if (libraryUri == null) return false;

    // Filter out dart: core library classes
    if (libraryUri!.startsWith('dart:')) return false;

    // Filter out Flutter framework classes
    if (libraryUri!.contains('package:flutter/')) return false;
    if (libraryUri!.contains('package:flutter_')) return false;

    // Filter out common framework/tool packages
    if (libraryUri!.contains('package:devtools')) return false;
    if (libraryUri!.contains('package:vm_service')) return false;

    // POSITIVE MATCH: Must be from a user package (package:something/)
    // and not from internal VM classes (which often have no package: prefix)
    if (!libraryUri!.startsWith('package:')) return false;

    // Common VM/runtime internal types to filter (even if they pass above checks)
    const internalTypes = {
      // Dart core types
      'String', 'List', 'Map', 'Set', 'int', 'double', 'bool',
      'Object', 'Type', 'Null', 'Function', 'Symbol',
      'Future', 'Stream', 'Completer', 'Timer',
      // VM internal types
      'Instructions', 'Code', 'Context', 'Closure',
      'TypeArguments', 'TypeParameters', 'TypeParameter',
      'OneByteString', 'TwoByteString', 'Uint8List',
      'ICData', 'PcDescriptors', 'ObjectPool', 'CodeSourceMap',
      'Class', 'Library', 'Script', 'Field', 'LocalVarDescriptors',
      'ExceptionHandlers', 'UnlinkedCall', 'MegamorphicCache',
      'SubtypeTestCache', 'LoadingUnit', 'WeakProperty', 'WeakReference',
      'FinalizerEntry', 'MirrorReference', 'UserTag',
    };

    if (internalTypes.contains(className)) return false;

    return true;
  }

  AllocationSample redacted({bool keepClassName = false}) {
    return AllocationSample(
      className: keepClassName ? className : 'Type_${className.hashCode.abs() % 1000}',
      libraryUri: null, // Always redact paths
      instanceCount: instanceCount,
      totalBytes: totalBytes,
      accumulatedBytes: accumulatedBytes,
      // Keep source location display path but not full path
      sourceLocation: sourceLocation,
      retentionInfo: retentionInfo,
      allocationSites: allocationSites,
      classId: classId,
      // CRITICAL: Cache the isUserClass value before libraryUri is nulled
      isUserClassCached: isUserClass,
    );
  }

  /// Creates a copy with enhanced analysis data.
  AllocationSample copyWith({
    CodeLocation? sourceLocation,
    RetentionInfo? retentionInfo,
    List<AllocationSite>? allocationSites,
  }) {
    return AllocationSample(
      className: className,
      libraryUri: libraryUri,
      instanceCount: instanceCount,
      totalBytes: totalBytes,
      accumulatedBytes: accumulatedBytes,
      sourceLocation: sourceLocation ?? this.sourceLocation,
      retentionInfo: retentionInfo ?? this.retentionInfo,
      allocationSites: allocationSites ?? this.allocationSites,
      classId: classId,
      isUserClassCached: _isUserClassCached,
    );
  }

  Map<String, dynamic> toJson() => {
        'className': className,
        if (libraryUri != null) 'libraryUri': libraryUri,
        'instanceCount': instanceCount,
        'totalBytes': totalBytes,
        'accumulatedBytes': accumulatedBytes,
        if (sourceLocation != null) 'sourceLocation': sourceLocation!.toJson(),
        if (retentionInfo != null) 'retentionInfo': retentionInfo!.toJson(),
        if (allocationSites != null)
          'allocationSites': allocationSites!.map((s) => s.toJson()).toList(),
      };
}

/// Timeline data for frame rendering analysis.
class TimelineData {
  final List<FrameTiming> frames;
  final int totalFrames;
  final int jankFrameCount;
  final double averageFrameTimeMs;
  final double p95FrameTimeMs;
  final double p99FrameTimeMs;
  final List<SlowTimelineEvent> slowEvents; // NEW: Slow operations causing jank

  TimelineData({
    required this.frames,
    required this.totalFrames,
    required this.jankFrameCount,
    required this.averageFrameTimeMs,
    required this.p95FrameTimeMs,
    required this.p99FrameTimeMs,
    this.slowEvents = const [],
  });

  double get jankPercent => totalFrames > 0 ? (jankFrameCount / totalFrames) * 100 : 0;

  /// Timeline data is already aggregated, minimal redaction needed.
  TimelineData redacted() => this;

  Map<String, dynamic> toJson() => {
        'totalFrames': totalFrames,
        'jankFrameCount': jankFrameCount,
        'jankPercent': jankPercent.toStringAsFixed(1),
        'averageFrameTimeMs': averageFrameTimeMs.toStringAsFixed(2),
        'p95FrameTimeMs': p95FrameTimeMs.toStringAsFixed(2),
        'p99FrameTimeMs': p99FrameTimeMs.toStringAsFixed(2),
        'recentFrames': frames.take(20).map((f) => f.toJson()).toList(),
        if (slowEvents.isNotEmpty)
          'slowOperations': slowEvents.take(15).map((e) => e.toJson()).toList(),
      };
}

/// Represents a slow timeline event that may be causing jank.
class SlowTimelineEvent {
  final String name;
  final int durationUs;
  final int timestamp;
  final String category; // 'build', 'layout', 'paint', 'raster', 'gc', 'other'
  final Map<String, dynamic>? args;

  SlowTimelineEvent({
    required this.name,
    required this.durationUs,
    required this.timestamp,
    required this.category,
    this.args,
  });

  double get durationMs => durationUs / 1000;

  Map<String, dynamic> toJson() => {
        'name': name,
        'durationMs': durationMs.toStringAsFixed(2),
        'category': category,
        if (args != null && args!.isNotEmpty)
          'details': _extractRelevantArgs(args!),
      };

  /// Extract relevant information from event args (filter out noise).
  Map<String, dynamic> _extractRelevantArgs(Map<String, dynamic> args) {
    final relevant = <String, dynamic>{};
    for (final key in args.keys) {
      final value = args[key];
      // Keep strings that look like class/function names
      if (value is String && value.isNotEmpty && !value.contains('/') && value.length < 100) {
        relevant[key] = value;
      }
      // Keep small numbers (could be counts, sizes, etc.)
      if (value is int && value < 1000000) {
        relevant[key] = value;
      }
    }
    return relevant;
  }
}

/// Individual frame timing information.
class FrameTiming {
  final int buildTimeUs;
  final int rasterTimeUs;
  final int totalTimeUs;
  final bool isJank;

  FrameTiming({
    required this.buildTimeUs,
    required this.rasterTimeUs,
    required this.totalTimeUs,
    required this.isJank,
  });

  double get buildTimeMs => buildTimeUs / 1000;
  double get rasterTimeMs => rasterTimeUs / 1000;
  double get totalTimeMs => totalTimeUs / 1000;

  Map<String, dynamic> toJson() => {
        'buildTimeMs': buildTimeMs.toStringAsFixed(2),
        'rasterTimeMs': rasterTimeMs.toStringAsFixed(2),
        'totalTimeMs': totalTimeMs.toStringAsFixed(2),
        'isJank': isJank,
      };
}
