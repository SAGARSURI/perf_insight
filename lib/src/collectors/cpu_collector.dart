/// CPU profiling data collector.
///
/// Handles CPU sample collection, profiling status checks,
/// and function source location resolution.

import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

import '../models/performance_data.dart';

/// Status of CPU profiling availability.
class CpuProfilingStatus {
  final bool isAvailable;
  final int sampleCount;
  final int functionCount;
  final String message;
  final String hint;
  final String? error;

  const CpuProfilingStatus({
    required this.isAvailable,
    this.sampleCount = 0,
    this.functionCount = 0,
    required this.message,
    required this.hint,
    this.error,
  });

  bool get hasData => sampleCount > 0;
}

/// Collects CPU profiling data from the VM service.
class CpuCollector {
  final VmService _vmService;
  bool _profilingEnabled = false;

  CpuCollector(this._vmService);

  /// Whether CPU profiling has been enabled.
  bool get isEnabled => _profilingEnabled;

  /// Enable CPU profiling on the VM.
  Future<void> enableProfiling(String isolateId) async {
    if (_profilingEnabled) return;

    try {
      debugPrint('CPU: Enabling profiling for isolate $isolateId');

      // Set a reasonable sample period (250 microseconds = 4000 samples/sec)
      try {
        await _vmService.callMethod('setProfilePeriod', args: {'period': 250});
        debugPrint('CPU: Profile period set to 250 microseconds');
      } catch (e) {
        debugPrint('CPU: Could not set profile period: $e');
      }

      // Clear any old samples to start fresh
      try {
        await _vmService.clearCpuSamples(isolateId);
        debugPrint('CPU: Cleared old samples');
      } catch (e) {
        debugPrint('CPU: Could not clear samples: $e');
      }

      _profilingEnabled = true;
      debugPrint('CPU profiling enabled');
    } catch (e) {
      debugPrint('Could not enable profiling: $e');
    }
  }

  /// Check if CPU profiling is available and working.
  Future<CpuProfilingStatus> checkStatus(String isolateId) async {
    try {
      final vm = await _vmService.getVM();
      debugPrint('CPU Status: VM version ${vm.version}');

      final now = DateTime.now().microsecondsSinceEpoch;
      final samples = await _vmService.getCpuSamples(
        isolateId,
        now - 1000000, // Last 1 second
        1000000,
      );

      final sampleCount = samples.samples?.length ?? 0;
      final functionCount = samples.functions?.length ?? 0;

      if (sampleCount > 0) {
        return CpuProfilingStatus(
          isAvailable: true,
          sampleCount: sampleCount,
          functionCount: functionCount,
          message: 'CPU profiling active',
          hint: '$sampleCount samples collected in last second',
        );
      } else {
        return CpuProfilingStatus(
          isAvailable: true,
          sampleCount: 0,
          functionCount: functionCount,
          message: 'CPU profiler ready but no samples yet',
          hint: 'Interact with your app to generate CPU activity, then analyze again.',
        );
      }
    } catch (e) {
      debugPrint('CPU Status check error: $e');
      return CpuProfilingStatus(
        isAvailable: false,
        message: 'CPU profiling unavailable',
        hint: 'Run your app with: flutter run --profile',
        error: e.toString(),
      );
    }
  }

  /// Collect CPU profiling data.
  Future<CpuData?> collect(String isolateId) async {
    try {
      debugPrint('CPU: Checking profiler availability...');

      // Log isolate info for debugging
      try {
        final isolate = await _vmService.getIsolate(isolateId);
        debugPrint('CPU: Isolate ${isolate.name} - pauseOnExit: ${isolate.pauseOnExit}');
        debugPrint('CPU: Isolate runnable: ${isolate.runnable}');
      } catch (e) {
        debugPrint('CPU: Could not get isolate info: $e');
      }

      // Get CPU samples from the last 10 seconds
      final now = DateTime.now().microsecondsSinceEpoch;
      final tenSecondsAgo = now - (10 * 1000 * 1000);

      debugPrint('CPU: Collecting samples from last 10 seconds...');

      final samples = await _vmService.getCpuSamples(
        isolateId,
        tenSecondsAgo,
        10 * 1000 * 1000,
      );

      debugPrint('CPU: Got ${samples.samples?.length ?? 0} samples, ${samples.functions?.length ?? 0} functions');

      if (samples.samples == null || samples.samples!.isEmpty) {
        _logNoSamplesReason();
        return null;
      }

      return _processSamples(samples);
    } catch (e) {
      debugPrint('CPU collection error: $e');
      return null;
    }
  }

  /// Get source location for a function.
  Future<CodeLocation?> getFunctionSourceLocation(
    String isolateId,
    String functionId,
  ) async {
    try {
      debugPrint('getFunctionSourceLocation: Getting function $functionId');

      final funcObj = await _vmService.getObject(isolateId, functionId);

      if (funcObj is! Func) {
        debugPrint('getFunctionSourceLocation: Object is not a Func');
        return null;
      }

      final location = funcObj.location;
      if (location == null) {
        debugPrint('getFunctionSourceLocation: No location for function');
        return null;
      }

      final scriptRef = location.script;
      if (scriptRef?.uri == null) {
        debugPrint('getFunctionSourceLocation: No script URI');
        return null;
      }

      final script = await _vmService.getObject(isolateId, scriptRef!.id!);

      int lineNumber = 1;
      String? codeSnippet;

      if (script is Script) {
        if (location.tokenPos != null) {
          lineNumber = script.getLineNumberFromTokenPos(location.tokenPos!) ?? 1;
        }

        if (script.source != null) {
          final lines = script.source!.split('\n');
          final startLine = (lineNumber - 1).clamp(0, lines.length - 1);
          final endLine = (startLine + 30).clamp(0, lines.length);
          codeSnippet = lines.sublist(startLine, endLine).join('\n');
        }
      }

      return CodeLocation(
        filePath: scriptRef.uri!,
        lineNumber: lineNumber,
        functionName: funcObj.name,
        className: funcObj.owner is ClassRef ? (funcObj.owner as ClassRef).name : null,
        codeSnippet: codeSnippet,
      );
    } catch (e) {
      debugPrint('getFunctionSourceLocation ERROR: $e');
      return null;
    }
  }

  /// Enhance CPU data with source locations for user functions.
  Future<CpuData?> enhanceWithSourceLocations(
    String isolateId,
    CpuData basic,
  ) async {
    final userFunctionsToEnhance = basic.topFunctions
        .where((f) => f.isUserFunction && f.functionId != null)
        .toList();

    // Fetch source locations in parallel
    final enhancedResults = await Future.wait(
      userFunctionsToEnhance.map((func) async {
        try {
          final sourceLocation = await getFunctionSourceLocation(
            isolateId,
            func.functionId!,
          );
          return func.copyWith(sourceLocation: sourceLocation);
        } catch (e) {
          return func;
        }
      }),
    );

    // Rebuild the list maintaining original order
    final enhancedFunctions = basic.topFunctions.map((func) {
      if (func.isUserFunction && func.functionId != null) {
        final enhanced = enhancedResults.firstWhere(
          (e) => e.functionId == func.functionId,
          orElse: () => func,
        );
        return enhanced;
      }
      return func;
    }).toList();

    return CpuData(
      sampleCount: basic.sampleCount,
      samplePeriodMicros: basic.samplePeriodMicros,
      maxStackDepth: basic.maxStackDepth,
      totalCpuTimeMs: basic.totalCpuTimeMs,
      topFunctions: enhancedFunctions,
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _logNoSamplesReason() {
    debugPrint('CPU: ⚠️ NO SAMPLES COLLECTED!');
    debugPrint('CPU: Possible reasons:');
    debugPrint('CPU: 1. App not running in profile mode (flutter run --profile)');
    debugPrint('CPU: 2. App is idle - interact with the app to generate CPU activity');
    debugPrint('CPU: 3. Profiler not supported on this platform/device');
    debugPrint('CPU: 4. Samples cleared too recently');
  }

  CpuData _processSamples(CpuSamples samples) {
    final functionCounts = <String, _FunctionStats>{};
    final totalTicks = samples.samples!.length;

    for (final sample in samples.samples!) {
      if (sample.stack != null && sample.stack!.isNotEmpty) {
        // Count exclusive time for top of stack
        final topFrameIndex = sample.stack!.first;
        final function = _getFunctionInfo(samples, topFrameIndex);
        final key = '${function.className ?? ''}.${function.name}';

        functionCounts.putIfAbsent(key, () => _FunctionStats(function));
        functionCounts[key]!.exclusiveTicks++;

        // Count inclusive time for all frames in stack
        for (final frameIndex in sample.stack!) {
          final func = _getFunctionInfo(samples, frameIndex);
          final k = '${func.className ?? ''}.${func.name}';
          functionCounts.putIfAbsent(k, () => _FunctionStats(func));
          functionCounts[k]!.inclusiveTicks++;
        }
      }
    }

    // Sort by exclusive ticks and take top functions
    final sortedFunctions = functionCounts.values.toList()
      ..sort((a, b) => b.exclusiveTicks.compareTo(a.exclusiveTicks));

    final topFunctions = sortedFunctions.take(20).map((stats) {
      return FunctionSample(
        functionName: stats.function.name ?? 'unknown',
        className: stats.function.className,
        libraryUri: stats.function.libraryUri,
        exclusiveTicks: stats.exclusiveTicks,
        inclusiveTicks: stats.inclusiveTicks,
        percentage: totalTicks > 0 ? (stats.exclusiveTicks / totalTicks) * 100 : 0,
        functionId: stats.function.functionId,
      );
    }).toList();

    // Debug logging
    final userFuncs = topFunctions.where((f) => f.isUserFunction).toList();
    debugPrint('CPU: Total functions: ${topFunctions.length}, User functions: ${userFuncs.length}');

    return CpuData(
      sampleCount: totalTicks,
      samplePeriodMicros: samples.samplePeriod ?? 1000,
      maxStackDepth: samples.maxStackDepth ?? 0,
      totalCpuTimeMs: (totalTicks * (samples.samplePeriod ?? 1000)) / 1000,
      topFunctions: topFunctions,
    );
  }

  _FunctionInfo _getFunctionInfo(CpuSamples samples, int index) {
    final functions = samples.functions;
    if (functions == null || index >= functions.length) {
      return _FunctionInfo('unknown', null, null, null);
    }

    final profileFunction = functions[index];
    final funcRef = profileFunction.function;

    String? name;
    String? className;
    String? libraryUri;
    String? functionId;

    if (funcRef is FuncRef) {
      name = funcRef.name;
      functionId = funcRef.id;
      final owner = funcRef.owner;
      if (owner is ClassRef) {
        className = owner.name;
        libraryUri = owner.library?.uri;
      } else if (owner is LibraryRef) {
        libraryUri = owner.uri;
      }
    }

    return _FunctionInfo(name ?? 'unknown', className, libraryUri, functionId);
  }
}

/// Helper class for function information.
class _FunctionInfo {
  final String? name;
  final String? className;
  final String? libraryUri;
  final String? functionId;

  _FunctionInfo(this.name, this.className, this.libraryUri, this.functionId);
}

/// Helper class for aggregating function statistics.
class _FunctionStats {
  final _FunctionInfo function;
  int exclusiveTicks = 0;
  int inclusiveTicks = 0;

  _FunctionStats(this.function);
}
