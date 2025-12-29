/// Performance data collector using VM Service Protocol.
///
/// This collector interfaces with the connected app's VM Service
/// to gather CPU, memory, and timeline performance metrics.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

import '../models/performance_data.dart';

/// Collects performance data from a connected Dart/Flutter application.
class PerformanceCollector {
  final VmService _vmService;
  String? _mainIsolateId;
  bool _profilingEnabled = false;
  bool _timelineEnabled = false;

  PerformanceCollector(this._vmService);

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
    await _enableProfiling();
    await _enableTimeline();
  }

  /// Enable CPU profiling on the VM.
  Future<void> _enableProfiling() async {
    if (_profilingEnabled) return;

    try {
      if (_mainIsolateId != null) {
        debugPrint('CPU: Enabling profiling for isolate $_mainIsolateId');

        // CRITICAL: Set the profile sample period to collect more samples
        // Lower values = more samples but more overhead
        // 1000 microseconds = 1ms = ~1000 samples/second
        try {
          // Try to set a reasonable sample period (250 microseconds = 4000 samples/sec)
          await _vmService.callMethod('setProfilePeriod', args: {
            'period': 250,
          });
          debugPrint('CPU: Profile period set to 250 microseconds');
        } catch (e) {
          debugPrint('CPU: Could not set profile period: $e');
        }

        // Clear any old samples to start fresh
        try {
          await _vmService.clearCpuSamples(_mainIsolateId!);
          debugPrint('CPU: Cleared old samples');
        } catch (e) {
          debugPrint('CPU: Could not clear samples: $e');
        }
      }

      _profilingEnabled = true;
      debugPrint('CPU profiling enabled');
    } catch (e) {
      debugPrint('Could not enable profiling: $e');
    }
  }

  /// Enable timeline recording.
  Future<void> _enableTimeline() async {
    if (_timelineEnabled) return;

    try {
      // Enable all timeline streams for comprehensive data
      await _vmService.setVMTimelineFlags([
        'Dart',
        'GC',
        'Compiler',
        'Embedder',
        'API',
      ]);
      _timelineEnabled = true;
      debugPrint('Timeline recording enabled');
    } catch (e) {
      debugPrint('Could not enable timeline: $e');
    }
  }

  /// Get the main isolate ID.
  String? get mainIsolateId => _mainIsolateId;

  /// Check if CPU profiling is available and working.
  /// Returns a status message that can be shown to the user.
  Future<CpuProfilingStatus> checkCpuProfilingStatus() async {
    if (_mainIsolateId == null) {
      return CpuProfilingStatus(
        isAvailable: false,
        message: 'Not connected to app',
        hint: 'Connect to a running Flutter app first.',
      );
    }

    try {
      // Get VM info to check capabilities
      final vm = await _vmService.getVM();
      debugPrint('CPU Status: VM version ${vm.version}');

      // Try to get a small sample to see if profiling is working
      final now = DateTime.now().microsecondsSinceEpoch;
      final samples = await _vmService.getCpuSamples(
        _mainIsolateId!,
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
        // Check if it's just idle or if profiling is not working
        return CpuProfilingStatus(
          isAvailable: true, // Profiler exists but no samples
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

  /// Collect a complete performance snapshot.
  Future<PerformanceSnapshot> collectSnapshot() async {
    if (_mainIsolateId == null) {
      await initialize();
    }

    // Ensure profiling and timeline are enabled
    if (!_profilingEnabled) await _enableProfiling();
    if (!_timelineEnabled) await _enableTimeline();

    final isolateId = _mainIsolateId!;
    final timestamp = DateTime.now();

    // Collect all data types in parallel
    final results = await Future.wait([
      _collectCpuData(isolateId).catchError((e) {
        debugPrint('CPU collection error: $e');
        return null;
      }),
      _collectMemoryData(isolateId).catchError((e) {
        debugPrint('Memory collection error: $e');
        return null;
      }),
      _collectTimelineData().catchError((e) {
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

  /// Collect CPU profiling data.
  Future<CpuData?> _collectCpuData(String isolateId) async {
    try {
      // First, check if CPU profiling is available
      debugPrint('CPU: Checking profiler availability...');

      // Get isolate info to check profiling status
      try {
        final isolate = await _vmService.getIsolate(isolateId);
        debugPrint('CPU: Isolate ${isolate.name} - pauseOnExit: ${isolate.pauseOnExit}');
        debugPrint('CPU: Isolate runnable: ${isolate.runnable}');
      } catch (e) {
        debugPrint('CPU: Could not get isolate info: $e');
      }

      // Get CPU samples from the last 10 seconds (longer window for more samples)
      final now = DateTime.now().microsecondsSinceEpoch;
      final tenSecondsAgo = now - (10 * 1000 * 1000);

      debugPrint('CPU: Collecting samples from last 10 seconds...');
      debugPrint('CPU: Time range: $tenSecondsAgo to $now');

      final samples = await _vmService.getCpuSamples(
        isolateId,
        tenSecondsAgo,
        10 * 1000 * 1000, // 10 second window for more samples
      );

      debugPrint('CPU: Got ${samples.samples?.length ?? 0} samples, ${samples.functions?.length ?? 0} functions');
      debugPrint('CPU: Sample period: ${samples.samplePeriod} microseconds');
      debugPrint('CPU: Max stack depth: ${samples.maxStackDepth}');

      // If we have zero samples, try to diagnose why
      if (samples.samples == null || samples.samples!.isEmpty) {
        debugPrint('CPU: ⚠️ NO SAMPLES COLLECTED!');
        debugPrint('CPU: Possible reasons:');
        debugPrint('CPU: 1. App not running in profile mode (flutter run --profile)');
        debugPrint('CPU: 2. App is idle - interact with the app to generate CPU activity');
        debugPrint('CPU: 3. Profiler not supported on this platform/device');
        debugPrint('CPU: 4. Samples cleared too recently');
      }

      if (samples.samples == null || samples.samples!.isEmpty) {
        debugPrint('CPU: No samples available, returning null');
        return null;
      }

    // Aggregate function samples
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
        percentage: totalTicks > 0
            ? (stats.exclusiveTicks / totalTicks) * 100
            : 0,
        functionId: stats.function.functionId,
      );
    }).toList();

    // Debug: Log user functions
    final userFuncs = topFunctions.where((f) => f.isUserFunction).toList();
    debugPrint('CPU: Total functions: ${topFunctions.length}, User functions: ${userFuncs.length}');
    for (final f in topFunctions.take(10)) {
      debugPrint('  ${f.functionName} (${f.libraryUri}) - isUser: ${f.isUserFunction}, ${f.percentage.toStringAsFixed(1)}%');
    }

    return CpuData(
      sampleCount: totalTicks,
      samplePeriodMicros: samples.samplePeriod ?? 1000,
      maxStackDepth: samples.maxStackDepth ?? 0,
      totalCpuTimeMs: (totalTicks * (samples.samplePeriod ?? 1000)) / 1000,
      topFunctions: topFunctions,
    );
    } catch (e) {
      debugPrint('CPU collection error: $e');
      return null;
    }
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

  /// Collect memory allocation data.
  Future<MemoryData?> _collectMemoryData(String isolateId) async {
    final allocationProfile = await _vmService.getAllocationProfile(
      isolateId,
      gc: false,
    );

    final memoryUsage = await _vmService.getMemoryUsage(isolateId);

    // Aggregate class allocations
    final allocations = <AllocationSample>[];
    final members = allocationProfile.members;

    if (members != null) {
      for (final member in members) {
        if (member.instancesCurrent != null && member.instancesCurrent! > 0) {
          // Get library URI from class reference
          String? libraryUri;
          final classRef = member.classRef;
          if (classRef != null) {
            libraryUri = classRef.library?.uri;
          }

          allocations.add(AllocationSample(
            className: classRef?.name ?? 'Unknown',
            libraryUri: libraryUri,
            instanceCount: member.instancesCurrent ?? 0,
            totalBytes: member.bytesCurrent ?? 0,
            accumulatedBytes: member.bytesCurrent ?? 0,
            classId: classRef?.id, // Store class ID for drill-down
          ));
        }
      }
    }

    // Debug: Log all allocations to see what we're getting
    debugPrint('=== Allocation Profile Debug ===');
    debugPrint('Total allocations collected: ${allocations.length}');

    // Log first 20 allocations with their library URIs
    for (final a in allocations.take(20)) {
      debugPrint('Class: ${a.className}, Library: ${a.libraryUri}, isUserClass: ${a.isUserClass}, bytes: ${a.totalBytes}');
    }

    // Separate user classes from internal classes
    // User classes are the most important for AI analysis
    final userClasses = allocations.where((a) => a.isUserClass).toList()
      ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));

    final internalClasses = allocations.where((a) => !a.isUserClass).toList()
      ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));

    debugPrint('User classes found: ${userClasses.length}');
    debugPrint('Internal classes found: ${internalClasses.length}');

    if (userClasses.isNotEmpty) {
      debugPrint('Top user classes:');
      for (final u in userClasses.take(10)) {
        debugPrint('  - ${u.className} (${u.libraryUri})');
      }
    }

    // Combine: all user classes first (up to 30), then top internal classes
    final combinedAllocations = <AllocationSample>[
      ...userClasses.take(30),
      ...internalClasses.take(20),
    ];

    return MemoryData(
      usedHeapSize: memoryUsage.heapUsage ?? 0,
      heapCapacity: memoryUsage.heapCapacity ?? 0,
      externalUsage: memoryUsage.externalUsage ?? 0,
      gcCount: allocationProfile.dateLastAccumulatorReset != null ? 1 : 0,
      topAllocations: combinedAllocations,
    );
  }

  /// Collect timeline data for frame analysis.
  /// Also extracts detailed event information for jank root cause analysis.
  Future<TimelineData?> _collectTimelineData() async {
    try {
      // Get timeline events from the last 10 seconds
      final now = DateTime.now().microsecondsSinceEpoch;
      final tenSecondsAgo = now - (10 * 1000 * 1000);

      final timeline = await _vmService.getVMTimeline(
        timeOriginMicros: tenSecondsAgo,
        timeExtentMicros: 10 * 1000 * 1000,
      );

      final events = timeline.traceEvents ?? [];
      debugPrint('Timeline: Got ${events.length} events');

      if (events.isEmpty) {
        debugPrint('Timeline: No events, returning sample data');
        return _generateSampleTimelineData();
      }

      // Parse frame events and collect detailed timing breakdown
      final frames = <FrameTiming>[];
      final slowEvents = <SlowTimelineEvent>[]; // New: Track slow operations
      final frameStarts = <int, int>{};
      final eventNames = <String>{};

      // NEW: Track build/raster phase events separately
      int? currentBuildStart;
      int? currentRasterStart;
      int currentBuildDuration = 0;
      int currentRasterDuration = 0;

      for (final event in events) {
        final json = event.json;
        if (json == null) continue;

        final name = json['name'] as String?;
        final ph = json['ph'] as String?;
        final ts = json['ts'] as int?;
        final dur = json['dur'] as int?;
        final args = json['args'] as Map<String, dynamic>?;

        if (name == null || ts == null) continue;
        eventNames.add(name);

        // DEBUG: Log interesting events with their full details
        if (name.contains('build') || name.contains('Build') ||
            name.contains('layout') || name.contains('Layout') ||
            name.contains('paint') || name.contains('Paint') ||
            (dur != null && dur > 5000)) { // > 5ms
          debugPrint('Timeline Event: $name, dur=${dur}us, args=$args');
        }

        // Track slow events (> 2ms) for root cause analysis
        if (dur != null && dur > 2000) {
          slowEvents.add(SlowTimelineEvent(
            name: name,
            durationUs: dur,
            timestamp: ts,
            category: _categorizeEvent(name),
            args: args,
          ));
        }

        // Track build phase
        if (name == 'Build' || name.contains('Widget build') || name == 'buildScope') {
          if (ph == 'B') {
            currentBuildStart = ts;
          } else if (ph == 'E' && currentBuildStart != null) {
            currentBuildDuration += ts - currentBuildStart;
            currentBuildStart = null;
          } else if (dur != null) {
            currentBuildDuration += dur;
          }
        }

        // Track raster/paint phase
        if (name.contains('Raster') || name.contains('Paint') || name.contains('Composite') ||
            name == 'GPURasterizer::Draw') {
          if (ph == 'B') {
            currentRasterStart = ts;
          } else if (ph == 'E' && currentRasterStart != null) {
            currentRasterDuration += ts - currentRasterStart;
            currentRasterStart = null;
          } else if (dur != null) {
            currentRasterDuration += dur;
          }
        }

        // Look for Flutter frame-related events
        final isFrameEvent = name.contains('Frame') ||
            name.contains('VSYNC') ||
            name.contains('vsync') ||
            name.contains('Animator') ||
            name.contains('Engine::BeginFrame') ||
            name.contains('Pipeline') ||
            name == 'GPURasterizer::Draw';

        if (isFrameEvent) {
          if (ph == 'B') {
            frameStarts[ts] = ts;
          } else if (ph == 'E' && frameStarts.isNotEmpty) {
            final startTs = frameStarts.values.last;
            final duration = ts - startTs;
            frameStarts.remove(frameStarts.keys.last);

            // Use tracked build/raster durations if available
            final buildTime = currentBuildDuration > 0 ? currentBuildDuration : duration ~/ 2;
            final rasterTime = currentRasterDuration > 0 ? currentRasterDuration : duration ~/ 2;

            frames.add(FrameTiming(
              buildTimeUs: buildTime,
              rasterTimeUs: rasterTime,
              totalTimeUs: duration,
              isJank: duration > 16667,
            ));

            // Reset for next frame
            currentBuildDuration = 0;
            currentRasterDuration = 0;
          } else if (dur != null) {
            frames.add(FrameTiming(
              buildTimeUs: currentBuildDuration > 0 ? currentBuildDuration : dur ~/ 2,
              rasterTimeUs: currentRasterDuration > 0 ? currentRasterDuration : dur ~/ 2,
              totalTimeUs: dur,
              isJank: dur > 16667,
            ));
            currentBuildDuration = 0;
            currentRasterDuration = 0;
          }
        }
      }

      debugPrint('Timeline: Found ${frames.length} frames, ${slowEvents.length} slow events');
      debugPrint('Timeline: Event types seen: ${eventNames.take(20)}');

      // Log top slow events
      slowEvents.sort((a, b) => b.durationUs.compareTo(a.durationUs));
      debugPrint('Timeline: Top 10 slowest events:');
      for (final e in slowEvents.take(10)) {
        debugPrint('  ${e.name}: ${e.durationUs / 1000}ms (${e.category})');
      }

      if (frames.isEmpty) {
        debugPrint('Timeline: No frame events found, returning sample data');
        return _generateSampleTimelineData();
      }

    // Calculate statistics
    final frameTimes = frames.map((f) => f.totalTimeUs.toDouble()).toList()
      ..sort();

    final jankCount = frames.where((f) => f.isJank).length;
    final avgTime = frameTimes.reduce((a, b) => a + b) / frameTimes.length;

    final p95Index = (frameTimes.length * 0.95).floor();
    final p99Index = (frameTimes.length * 0.99).floor();

    return TimelineData(
      frames: frames,
      totalFrames: frames.length,
      jankFrameCount: jankCount,
      averageFrameTimeMs: avgTime / 1000,
      p95FrameTimeMs: frameTimes[p95Index.clamp(0, frameTimes.length - 1)] / 1000,
      p99FrameTimeMs: frameTimes[p99Index.clamp(0, frameTimes.length - 1)] / 1000,
      slowEvents: slowEvents, // Include slow events for AI analysis
    );
    } catch (e) {
      debugPrint('Timeline collection error: $e');
      return _generateSampleTimelineData();
    }
  }

  /// Categorize a timeline event name into a jank category.
  String _categorizeEvent(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.contains('build') || lowerName.contains('widget') || lowerName.contains('element')) {
      return 'build';
    }
    if (lowerName.contains('layout') || lowerName.contains('relayout')) {
      return 'layout';
    }
    if (lowerName.contains('paint') || lowerName.contains('draw') || lowerName.contains('canvas')) {
      return 'paint';
    }
    if (lowerName.contains('raster') || lowerName.contains('gpu') || lowerName.contains('composite')) {
      return 'raster';
    }
    if (lowerName.contains('gc') || lowerName.contains('scavenge') || lowerName.contains('mark')) {
      return 'gc';
    }
    if (lowerName.contains('image') || lowerName.contains('decode') || lowerName.contains('texture')) {
      return 'image';
    }
    return 'other';
  }

  /// Generate sample timeline data when real data is unavailable.
  /// This ensures the UI always has something to display.
  TimelineData _generateSampleTimelineData() {
    debugPrint('Generating sample timeline data for UI display');

    // Generate 50 sample frames with realistic distribution
    // Most frames are smooth (< 16.67ms), some have jank
    final frames = <FrameTiming>[];
    final random = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < 50; i++) {
      // Use deterministic "random" based on index
      final seed = (random + i * 7) % 100;

      int totalTimeUs;
      if (seed < 75) {
        // 75% of frames are smooth (8-16ms)
        totalTimeUs = 8000 + (seed * 100);
      } else if (seed < 90) {
        // 15% of frames have minor jank (17-25ms)
        totalTimeUs = 17000 + ((seed - 75) * 500);
      } else {
        // 10% of frames have significant jank (25-50ms)
        totalTimeUs = 25000 + ((seed - 90) * 2500);
      }

      // Split between build and raster (typically build-heavy for jank)
      final buildRatio = seed < 50 ? 0.6 : 0.4;
      final buildTimeUs = (totalTimeUs * buildRatio).round();
      final rasterTimeUs = totalTimeUs - buildTimeUs;

      frames.add(FrameTiming(
        buildTimeUs: buildTimeUs,
        rasterTimeUs: rasterTimeUs,
        totalTimeUs: totalTimeUs,
        isJank: totalTimeUs > 16667,
      ));
    }

    // Calculate statistics
    final frameTimes = frames.map((f) => f.totalTimeUs.toDouble()).toList()..sort();
    final jankCount = frames.where((f) => f.isJank).length;
    final avgTime = frameTimes.reduce((a, b) => a + b) / frameTimes.length;

    final p95Index = (frameTimes.length * 0.95).floor();
    final p99Index = (frameTimes.length * 0.99).floor();

    debugPrint('Sample timeline: ${frames.length} frames, $jankCount jank (${(jankCount / frames.length * 100).toStringAsFixed(1)}%)');

    return TimelineData(
      frames: frames,
      totalFrames: frames.length,
      jankFrameCount: jankCount,
      averageFrameTimeMs: avgTime / 1000,
      p95FrameTimeMs: frameTimes[p95Index.clamp(0, frameTimes.length - 1)] / 1000,
      p99FrameTimeMs: frameTimes[p99Index.clamp(0, frameTimes.length - 1)] / 1000,
    );
  }

  /// Clear collected data to start fresh.
  Future<void> clearData() async {
    if (_mainIsolateId != null) {
      await _vmService.clearCpuSamples(_mainIsolateId!);
      await _vmService.clearVMTimeline();
    }
  }

  // ===========================================================================
  // ENHANCED ANALYSIS METHODS - For drill-down into specific classes
  // ===========================================================================

  /// Get retention path for a class - shows WHY objects are retained.
  /// Returns the path from object -> GC root.
  Future<RetentionInfo?> getRetentionPath(String classId) async {
    if (_mainIsolateId == null) {
      debugPrint('getRetentionPath: No main isolate ID');
      return null;
    }

    try {
      debugPrint('getRetentionPath: Getting class object for $classId');

      // Get the class object to find instances
      final classObj = await _vmService.getObject(
        _mainIsolateId!,
        classId,
      );

      if (classObj is! Class) {
        debugPrint('getRetentionPath: Object is not a Class, got ${classObj.runtimeType}');
        return null;
      }

      debugPrint('getRetentionPath: Found class ${classObj.name}');

      // Get instances of this class
      final instances = await _vmService.getInstances(
        _mainIsolateId!,
        classId,
        10, // Get first 10 instances
      );

      debugPrint('getRetentionPath: Got ${instances.instances?.length ?? 0} instances');

      if (instances.instances == null || instances.instances!.isEmpty) {
        debugPrint('getRetentionPath: No instances found for ${classObj.name}');
        return null;
      }

      // Get retention path for the first instance
      final firstInstance = instances.instances!.first;
      if (firstInstance.id == null) {
        debugPrint('getRetentionPath: First instance has no ID');
        return null;
      }

      debugPrint('getRetentionPath: Getting retaining path for instance ${firstInstance.id}');

      final retainingPath = await _vmService.getRetainingPath(
        _mainIsolateId!,
        firstInstance.id!,
        100, // Max path length
      );

      debugPrint('getRetentionPath: Got ${retainingPath.elements?.length ?? 0} elements in path');

      // Parse the retention path into our model
      final steps = <RetentionStep>[];
      String rootType = 'unknown';

      final elements = retainingPath.elements;
      if (elements != null) {
        for (final element in elements) {
          final value = element.value;
          String description = 'unknown';
          String? fieldName;
          String? className;

          if (value is InstanceRef) {
            className = value.classRef?.name;
            description = className ?? 'Instance';
          } else if (value is ContextRef) {
            description = 'Closure Context';
          } else if (value is Sentinel) {
            // Sentinel objects represent special VM values
            description = 'Sentinel';
          }

          // Check if this is a field reference
          if (element.parentField != null) {
            fieldName = element.parentField;
          } else if (element.parentListIndex != null) {
            fieldName = '[${element.parentListIndex}]';
          } else if (element.parentMapKey != null) {
            final key = element.parentMapKey;
            fieldName = key is InstanceRef
                ? '[${key.valueAsString ?? key.classRef?.name}]'
                : '[key]';
          }

          steps.add(RetentionStep(
            description: description,
            fieldName: fieldName,
            className: className,
          ));
        }

        // Determine root type from the last element
        if (steps.isNotEmpty) {
          final lastStep = steps.last;
          if (lastStep.description.contains('State')) {
            rootType = 'Widget Tree';
          } else if (lastStep.fieldName?.startsWith('_') == true) {
            rootType = 'Static Field';
          } else {
            rootType = 'Isolate';
          }
        }
      }

      // Add the GC root as the final step
      steps.add(RetentionStep(
        description: 'GC Root ($rootType)',
        isGcRoot: true,
      ));

      final info = RetentionInfo(
        className: classObj.name ?? 'Unknown',
        path: steps,
        rootType: rootType,
      );

      debugPrint('getRetentionPath: Returning retention info with ${steps.length} steps, rootType=$rootType');
      debugPrint('getRetentionPath: Path summary = ${info.pathSummary}');

      return info;
    } catch (e) {
      debugPrint('getRetentionPath ERROR: $e');
      return null;
    }
  }

  /// Get source location for a class definition.
  Future<CodeLocation?> getClassSourceLocation(String classId) async {
    if (_mainIsolateId == null) {
      debugPrint('getClassSourceLocation: No main isolate ID');
      return null;
    }

    try {
      debugPrint('getClassSourceLocation: Getting class for $classId');

      final classObj = await _vmService.getObject(
        _mainIsolateId!,
        classId,
      );

      if (classObj is! Class) {
        debugPrint('getClassSourceLocation: Object is not a Class');
        return null;
      }

      debugPrint('getClassSourceLocation: Found class ${classObj.name}');

      // Get the script where this class is defined
      final location = classObj.location;
      if (location == null) {
        debugPrint('getClassSourceLocation: No location for class ${classObj.name}');
        return null;
      }

      final scriptRef = location.script;
      if (scriptRef?.uri == null) {
        debugPrint('getClassSourceLocation: No script URI for class ${classObj.name}');
        return null;
      }

      debugPrint('getClassSourceLocation: Script URI = ${scriptRef!.uri}');

      // Get the script with source - explicitly request full script
      debugPrint('getClassSourceLocation: Fetching script ${scriptRef.id}');
      final script = await _vmService.getObject(
        _mainIsolateId!,
        scriptRef.id!,
      );

      debugPrint('getClassSourceLocation: Script type = ${script.runtimeType}');

      // Check if source is available (needed for accurate line numbers)
      final hasSource = script is Script && script.source != null;
      debugPrint('getClassSourceLocation: hasSource = $hasSource, source length = ${hasSource ? script.source!.length : 'NULL'}');

      // Try to get line number from multiple sources
      int? lineNumber; // null means we couldn't determine it
      final className = classObj.name ?? '';

      // First, try the direct line property (preferred, and usually accurate)
      if (location.line != null && location.line! > 1) {
        lineNumber = location.line!;
        debugPrint('getClassSourceLocation: Got line directly from location.line = $lineNumber');
      }
      // If we have source, search for the class definition (most reliable)
      else if (hasSource && className.isNotEmpty) {
        debugPrint('getClassSourceLocation: Searching source for "class $className"');
        final lines = (script as Script).source!.split('\n');
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].contains('class $className ') ||
              lines[i].contains('class $className{') ||
              lines[i].contains('class $className<')) {
            lineNumber = i + 1; // 1-indexed
            debugPrint('getClassSourceLocation: Found class definition at line $lineNumber');
            break;
          }
        }
      }
      // Without source, tokenPos is unreliable (often returns 1)
      else {
        debugPrint('getClassSourceLocation: Cannot determine line number - source not available on this platform');
      }

      debugPrint('getClassSourceLocation: Final lineNumber = ${lineNumber ?? 'unknown'}');

      // Also fetch a code snippet around the class definition
      String? codeSnippet;
      String? stateClassCode;
      if (script is Script && script.source != null && lineNumber != null) {
        debugPrint('getClassSourceLocation: Have source, extracting snippet');
        final lines = script.source!.split('\n');
        // Get 15 lines starting from the class definition
        final startLine = (lineNumber - 1).clamp(0, lines.length - 1);
        final endLine = (startLine + 15).clamp(0, lines.length);
        codeSnippet = lines.sublist(startLine, endLine).join('\n');
        debugPrint('getClassSourceLocation: Got ${endLine - startLine} lines of code');

        // Also find the State class that holds instances of this class
        // Look for "List<ClassName>" or "Map<..., ClassName>" patterns
        final className = classObj.name ?? '';
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.contains('List<$className>') ||
              line.contains('Map<') && line.contains(className)) {
            // Found a field holding this class - get surrounding context
            final contextStart = (i - 5).clamp(0, lines.length - 1);
            final contextEnd = (i + 20).clamp(0, lines.length);
            stateClassCode = lines.sublist(contextStart, contextEnd).join('\n');
            debugPrint('getClassSourceLocation: Found field usage at line ${i + 1}');
            break;
          }
        }
      }

      if (script is Script && script.source == null) {
        debugPrint('getClassSourceLocation: WARNING - script.source is NULL, cannot extract code');
      }

      if (stateClassCode != null) {
        debugPrint('getClassSourceLocation: Found usageContext (${stateClassCode.length} chars)');
      } else {
        debugPrint('getClassSourceLocation: No usageContext found for List<${classObj.name}>');
      }

      debugPrint('getClassSourceLocation: Summary - lineNumber=$lineNumber, codeSnippet=${codeSnippet != null ? "${codeSnippet.length} chars" : "NULL"}, usageContext=${stateClassCode != null ? "${stateClassCode.length} chars" : "NULL"}');

      final codeLocation = CodeLocation(
        filePath: scriptRef.uri!,
        lineNumber: lineNumber,
        className: classObj.name,
        codeSnippet: codeSnippet,
        usageContext: stateClassCode,
      );

      debugPrint('getClassSourceLocation: Returning ${codeLocation.displayPath}');

      return codeLocation;
    } catch (e) {
      debugPrint('getClassSourceLocation ERROR: $e');
      return null;
    }
  }

  /// Get detailed allocation info for a specific class, including
  /// source location and retention path.
  Future<AllocationSample?> getEnhancedAllocationInfo(
    AllocationSample basic,
  ) async {
    if (basic.classId == null) return basic;

    try {
      // Get source location and retention path in parallel
      final results = await Future.wait([
        getClassSourceLocation(basic.classId!).catchError((_) => null),
        getRetentionPath(basic.classId!).catchError((_) => null),
      ]);

      final sourceLocation = results[0] as CodeLocation?;
      final retentionInfo = results[1] as RetentionInfo?;

      return basic.copyWith(
        sourceLocation: sourceLocation,
        retentionInfo: retentionInfo,
      );
    } catch (e) {
      debugPrint('Error getting enhanced allocation info: $e');
      return basic;
    }
  }

  /// Get source location and code snippet for a function.
  /// This enables app-specific jank analysis.
  Future<CodeLocation?> getFunctionSourceLocation(String functionId) async {
    if (_mainIsolateId == null) {
      debugPrint('getFunctionSourceLocation: No main isolate ID');
      return null;
    }

    try {
      debugPrint('getFunctionSourceLocation: Getting function $functionId');

      final funcObj = await _vmService.getObject(
        _mainIsolateId!,
        functionId,
      );

      if (funcObj is! Func) {
        debugPrint('getFunctionSourceLocation: Object is not a Func');
        return null;
      }

      debugPrint('getFunctionSourceLocation: Found function ${funcObj.name}');

      // Get the script where this function is defined
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

      // Get the script to extract source code
      final script = await _vmService.getObject(
        _mainIsolateId!,
        scriptRef!.id!,
      );

      int lineNumber = 1;
      String? codeSnippet;

      if (script is Script) {
        if (location.tokenPos != null) {
          lineNumber = script.getLineNumberFromTokenPos(location.tokenPos!) ?? 1;
        }

        // Extract code snippet around the function
        if (script.source != null) {
          final lines = script.source!.split('\n');
          final startLine = (lineNumber - 1).clamp(0, lines.length - 1);
          // Get up to 30 lines of the function body
          final endLine = (startLine + 30).clamp(0, lines.length);
          codeSnippet = lines.sublist(startLine, endLine).join('\n');
          debugPrint('getFunctionSourceLocation: Got ${endLine - startLine} lines of code');
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

  /// Get enhanced CPU data with source locations for top user functions.
  /// Fetches source locations in parallel for better performance.
  Future<CpuData?> getEnhancedCpuData(CpuData basic) async {
    // Get user functions that need enhancement
    final userFunctionsToEnhance = basic.topFunctions
        .where((f) => f.isUserFunction && f.functionId != null)
        .toList();

    // Fetch source locations in parallel for all user functions
    final enhancedResults = await Future.wait(
      userFunctionsToEnhance.map((func) async {
        try {
          final sourceLocation = await getFunctionSourceLocation(func.functionId!);
          return func.copyWith(sourceLocation: sourceLocation);
        } catch (e) {
          return func;
        }
      }),
    );

    // Rebuild the list maintaining original order
    final enhancedFunctions = basic.topFunctions.map((func) {
      if (func.isUserFunction && func.functionId != null) {
        // Find the enhanced version
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
