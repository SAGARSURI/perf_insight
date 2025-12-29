/// Performance data collector using VM Service Protocol.
///
/// This collector is a facade that coordinates CPU, memory, and timeline
/// collectors to gather comprehensive performance metrics from a connected
/// Dart/Flutter application.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

import '../models/performance_data.dart';
import 'cpu_collector.dart';
import 'memory_collector.dart';
import 'timeline_collector.dart';

// Re-export for backwards compatibility
export 'cpu_collector.dart' show CpuProfilingStatus;

/// Collects performance data from a connected Dart/Flutter application.
///
/// This is the main entry point for performance data collection. It coordinates
/// three specialized collectors:
/// - [CpuCollector] for CPU profiling and function analysis
/// - [MemoryCollector] for heap allocation and retention analysis
/// - [TimelineCollector] for frame timing and jank detection
class PerformanceCollector {
  final VmService _vmService;

  late final CpuCollector _cpuCollector;
  late final MemoryCollector _memoryCollector;
  late final TimelineCollector _timelineCollector;

  String? _mainIsolateId;

  PerformanceCollector(this._vmService) {
    _cpuCollector = CpuCollector(_vmService);
    _memoryCollector = MemoryCollector(_vmService);
    _timelineCollector = TimelineCollector(_vmService);
  }

  /// Get the main isolate ID.
  String? get mainIsolateId => _mainIsolateId;

  /// Initialize the collector and find the main isolate.
  Future<void> initialize() async {
    final vm = await _vmService.getVM();
    final isolates = vm.isolates ?? [];

    // Find the main isolate (usually named 'main')
    for (final isolateRef in isolates) {
      final isolate = await _vmService.getIsolate(isolateRef.id!);
      if (isolate.name == 'main' || isolateRef.id == isolates.first.id) {
        _mainIsolateId = isolateRef.id;
        break;
      }
    }

    if (_mainIsolateId == null && isolates.isNotEmpty) {
      _mainIsolateId = isolates.first.id;
    }

    // Enable profiling and timeline
    if (_mainIsolateId != null) {
      await _cpuCollector.enableProfiling(_mainIsolateId!);
    }
    await _timelineCollector.enableTimeline();
  }

  /// Check if CPU profiling is available and working.
  Future<CpuProfilingStatus> checkCpuProfilingStatus() async {
    if (_mainIsolateId == null) {
      return const CpuProfilingStatus(
        isAvailable: false,
        message: 'Not connected to app',
        hint: 'Connect to a running Flutter app first.',
      );
    }
    return _cpuCollector.checkStatus(_mainIsolateId!);
  }

  /// Collect a complete performance snapshot.
  Future<PerformanceSnapshot> collectSnapshot() async {
    if (_mainIsolateId == null) {
      await initialize();
    }

    // Ensure profiling and timeline are enabled
    if (!_cpuCollector.isEnabled && _mainIsolateId != null) {
      await _cpuCollector.enableProfiling(_mainIsolateId!);
    }
    if (!_timelineCollector.isEnabled) {
      await _timelineCollector.enableTimeline();
    }

    final isolateId = _mainIsolateId!;
    final timestamp = DateTime.now();

    // Collect all data types in parallel
    final results = await Future.wait([
      _cpuCollector.collect(isolateId).catchError((e) {
        debugPrint('CPU collection error: $e');
        return null;
      }),
      _memoryCollector.collect(isolateId).catchError((e) {
        debugPrint('Memory collection error: $e');
        return null;
      }),
      _timelineCollector.collect().catchError((e) {
        debugPrint('Timeline collection error: $e');
        return null;
      }),
    ]);

    return PerformanceSnapshot(
      timestamp: timestamp,
      isolateId: isolateId,
      cpu: results[0] as CpuData?,
      memory: results[1] as MemoryData?,
      timeline: results[2] as TimelineData?,
    );
  }

  /// Clear collected data to start fresh.
  Future<void> clearData() async {
    if (_mainIsolateId != null) {
      await _vmService.clearCpuSamples(_mainIsolateId!);
      await _timelineCollector.clear();
    }
  }

  // ===========================================================================
  // Memory analysis methods (delegated to MemoryCollector)
  // ===========================================================================

  /// Get retention path for a class - shows WHY objects are retained.
  Future<RetentionInfo?> getRetentionPath(String classId) async {
    if (_mainIsolateId == null) {
      debugPrint('getRetentionPath: No main isolate ID');
      return null;
    }
    return _memoryCollector.getRetentionPath(_mainIsolateId!, classId);
  }

  /// Get source location for a class definition.
  Future<CodeLocation?> getClassSourceLocation(String classId) async {
    if (_mainIsolateId == null) {
      debugPrint('getClassSourceLocation: No main isolate ID');
      return null;
    }
    return _memoryCollector.getClassSourceLocation(_mainIsolateId!, classId);
  }

  /// Get detailed allocation info for a specific class.
  Future<AllocationSample?> getEnhancedAllocationInfo(
    AllocationSample basic,
  ) async {
    if (_mainIsolateId == null || basic.classId == null) return basic;
    return _memoryCollector.getEnhancedAllocationInfo(_mainIsolateId!, basic);
  }

  // ===========================================================================
  // CPU analysis methods (delegated to CpuCollector)
  // ===========================================================================

  /// Get source location for a function.
  Future<CodeLocation?> getFunctionSourceLocation(String functionId) async {
    if (_mainIsolateId == null) {
      debugPrint('getFunctionSourceLocation: No main isolate ID');
      return null;
    }
    return _cpuCollector.getFunctionSourceLocation(_mainIsolateId!, functionId);
  }

  /// Get enhanced CPU data with source locations for top user functions.
  Future<CpuData?> getEnhancedCpuData(CpuData basic) async {
    if (_mainIsolateId == null) return basic;
    return _cpuCollector.enhanceWithSourceLocations(_mainIsolateId!, basic);
  }
}
