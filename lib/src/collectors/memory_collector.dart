/// Memory/heap allocation data collector.
///
/// Handles memory usage collection, allocation profiling,
/// retention path analysis, and source location resolution.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

import '../models/performance_data.dart';
import '../services/code_context_service.dart';

/// Timeout for VM service calls in milliseconds.
const int _vmServiceTimeoutMs = 10000;

/// Collects memory and heap allocation data from the VM service.
class MemoryCollector {
  final VmService _vmService;
  final CodeContextService _codeContext;

  MemoryCollector(this._vmService) : _codeContext = CodeContextService(_vmService);

  /// Collect memory allocation data.
  Future<MemoryData?> collect(String isolateId) async {
    final allocationProfile = await _vmService
        .getAllocationProfile(isolateId, gc: false)
        .timeout(Duration(milliseconds: _vmServiceTimeoutMs));

    final memoryUsage = await _vmService
        .getMemoryUsage(isolateId)
        .timeout(Duration(milliseconds: _vmServiceTimeoutMs));

    // Aggregate class allocations
    final allocations = <AllocationSample>[];
    final members = allocationProfile.members;

    if (members != null) {
      for (final member in members) {
        if (member.instancesCurrent != null && member.instancesCurrent! > 0) {
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
            classId: classRef?.id,
          ));
        }
      }
    }

    _logAllocationDebug(allocations);

    // Separate and sort user vs internal classes
    final userClasses = allocations.where((a) => a.isUserClass).toList()
      ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));

    final internalClasses = allocations.where((a) => !a.isUserClass).toList()
      ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));

    // Combine: user classes first, then internal classes
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

  /// Get retention path for a class - shows WHY objects are retained.
  Future<RetentionInfo?> getRetentionPath(
    String isolateId,
    String classId,
  ) async {
    try {
      debugPrint('getRetentionPath: Getting class object for $classId');

      final classObj = await _vmService
          .getObject(isolateId, classId)
          .timeout(Duration(milliseconds: _vmServiceTimeoutMs));

      if (classObj is! Class) {
        debugPrint('getRetentionPath: Object is not a Class, got ${classObj.runtimeType}');
        return null;
      }

      debugPrint('getRetentionPath: Found class ${classObj.name}');

      // Get instances of this class
      final instances = await _vmService
          .getInstances(isolateId, classId, 10)
          .timeout(Duration(milliseconds: _vmServiceTimeoutMs));

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

      final retainingPath = await _vmService
          .getRetainingPath(isolateId, firstInstance.id!, 100)
          .timeout(Duration(milliseconds: _vmServiceTimeoutMs));

      debugPrint('getRetentionPath: Got ${retainingPath.elements?.length ?? 0} elements in path');

      return _parseRetentionPath(classObj.name ?? 'Unknown', retainingPath);
    } catch (e) {
      debugPrint('getRetentionPath ERROR: $e');
      return null;
    }
  }

  /// Get source location for a class definition.
  Future<CodeLocation?> getClassSourceLocation(
    String isolateId,
    String classId,
  ) async {
    try {
      debugPrint('getClassSourceLocation: Getting class for $classId');

      final classObj = await _vmService
          .getObject(isolateId, classId)
          .timeout(Duration(milliseconds: _vmServiceTimeoutMs));

      if (classObj is! Class) {
        debugPrint('getClassSourceLocation: Object is not a Class');
        return null;
      }

      debugPrint('getClassSourceLocation: Found class ${classObj.name}');

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

      final scriptObj = await _vmService
          .getObject(isolateId, scriptRef.id!)
          .timeout(Duration(milliseconds: _vmServiceTimeoutMs));

      final script = scriptObj is Script ? scriptObj : null;
      String? sourceCode = script?.source;
      debugPrint('getClassSourceLocation: VM source = ${sourceCode != null}');

      // If VM Service doesn't have source (profile mode), try DTD
      if (sourceCode == null && _codeContext.isDtdAvailable) {
        debugPrint('getClassSourceLocation: VM source NULL, trying DTD for ${scriptRef.uri}');
        sourceCode = await _codeContext.getFileSource(scriptRef.uri!);
        debugPrint('getClassSourceLocation: DTD source = ${sourceCode != null}');
      }

      int? lineNumber;
      String? codeSnippet;
      String? stateClassCode;
      final className = classObj.name ?? '';

      // Try to get line number from location first
      if (location.line != null && location.line! > 1) {
        lineNumber = location.line!;
        debugPrint('getClassSourceLocation: Got line from location.line = $lineNumber');
      } else if (sourceCode != null && className.isNotEmpty) {
        // Search for class in source code
        lineNumber = _findClassDefinitionLineInSource(sourceCode, className);
        debugPrint('getClassSourceLocation: Found line by searching = $lineNumber');
      }

      // Extract code snippets if source is available
      if (sourceCode != null && lineNumber != null) {
        codeSnippet = _extractCodeSnippetFromSource(sourceCode, lineNumber, 15);
        stateClassCode = _findFieldUsageContextInSource(sourceCode, className);
      }

      debugPrint('getClassSourceLocation: Final lineNumber = ${lineNumber ?? 'unknown'}, hasSnippet = ${codeSnippet != null}');

      return CodeLocation(
        filePath: scriptRef.uri!,
        lineNumber: lineNumber,
        className: classObj.name,
        codeSnippet: codeSnippet,
        usageContext: stateClassCode,
      );
    } catch (e) {
      debugPrint('getClassSourceLocation ERROR: $e');
      return null;
    }
  }

  /// Get enhanced allocation info including source location, retention path,
  /// and codebase usage context.
  Future<AllocationSample?> getEnhancedAllocationInfo(
    String isolateId,
    AllocationSample basic,
  ) async {
    if (basic.classId == null) return basic;

    try {
      // Fetch source location, retention path, and class usages in parallel
      final results = await Future.wait([
        getClassSourceLocation(isolateId, basic.classId!).catchError((_) => null),
        getRetentionPath(isolateId, basic.classId!).catchError((_) => null),
        _fetchClassUsages(basic.className, isolateId, basic.classId),
      ]);

      final sourceLocation = results[0] as CodeLocation?;
      final retentionInfo = results[1] as RetentionInfo?;
      final classUsages = results[2] as List<ClassUsageInfo>?;

      return basic.copyWith(
        sourceLocation: sourceLocation,
        retentionInfo: retentionInfo,
        classUsages: classUsages,
      );
    } catch (e) {
      debugPrint('Error getting enhanced allocation info: $e');
      return basic;
    }
  }

  /// Fetch where a class is used in the codebase using CodeContextService.
  Future<List<ClassUsageInfo>?> _fetchClassUsages(
    String className,
    String isolateId,
    String? classId,
  ) async {
    try {
      // Only fetch usages for user classes (skip internal Dart/Flutter classes)
      if (className.startsWith('_')) {
        debugPrint('_fetchClassUsages: Skipping $className (starts with _)');
        return null;
      }

      debugPrint('_fetchClassUsages: Fetching context for $className...');
      debugPrint('  DTD available: ${_codeContext.isDtdAvailable}');

      final context = await _codeContext.getClassContext(
        className,
        isolateId,
        classId,
      );

      debugPrint('  Found ${context.usages.length} usages');
      debugPrint('  Has classDefinition: ${context.classDefinition != null}');

      if (context.usages.isEmpty) {
        debugPrint('  No usages found, returning null');
        return null;
      }

      // Convert CodeContextService.ClassUsage to ClassUsageInfo
      final usages = context.usages.take(5).map((usage) {
        debugPrint('  Usage: ${usage.filePath}:${usage.lineNumber}');
        return ClassUsageInfo(
          filePath: usage.filePath,
          lineNumber: usage.lineNumber,
          lineContent: usage.lineContent,
          context: usage.context,
        );
      }).toList();

      debugPrint('  Returning ${usages.length} usages');
      return usages;
    } catch (e) {
      debugPrint('_fetchClassUsages ERROR for $className: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _logAllocationDebug(List<AllocationSample> allocations) {
    debugPrint('=== Allocation Profile Debug ===');
    debugPrint('Total allocations collected: ${allocations.length}');

    for (final a in allocations.take(20)) {
      debugPrint('Class: ${a.className}, Library: ${a.libraryUri}, isUserClass: ${a.isUserClass}, bytes: ${a.totalBytes}');
    }

    final userClasses = allocations.where((a) => a.isUserClass).toList();
    final internalClasses = allocations.where((a) => !a.isUserClass).toList();

    debugPrint('User classes found: ${userClasses.length}');
    debugPrint('Internal classes found: ${internalClasses.length}');

    if (userClasses.isNotEmpty) {
      debugPrint('Top user classes:');
      for (final u in userClasses.take(10)) {
        debugPrint('  - ${u.className} (${u.libraryUri})');
      }
    }
  }

  RetentionInfo _parseRetentionPath(String className, RetainingPath retainingPath) {
    final steps = <RetentionStep>[];
    String rootType = 'unknown';

    final elements = retainingPath.elements;
    if (elements != null) {
      for (final element in elements) {
        final value = element.value;
        String description = 'unknown';
        String? fieldName;
        String? stepClassName;

        if (value is InstanceRef) {
          stepClassName = value.classRef?.name;
          description = stepClassName ?? 'Instance';
        } else if (value is ContextRef) {
          description = 'Closure Context';
        } else if (value is Sentinel) {
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
          className: stepClassName,
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
      className: className,
      path: steps,
      rootType: rootType,
    );

    debugPrint('getRetentionPath: Path summary = ${info.pathSummary}');
    return info;
  }

  int? _findClassDefinitionLine(Script script, String className) {
    debugPrint('getClassSourceLocation: Searching source for "class $className"');
    final lines = script.source!.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains('class $className ') ||
          lines[i].contains('class $className{') ||
          lines[i].contains('class $className<')) {
        debugPrint('getClassSourceLocation: Found class definition at line ${i + 1}');
        return i + 1;
      }
    }
    return null;
  }

  String? _extractCodeSnippet(Script script, int lineNumber, int numLines) {
    final lines = script.source!.split('\n');
    final startLine = (lineNumber - 1).clamp(0, lines.length - 1);
    final endLine = (startLine + numLines).clamp(0, lines.length);
    return lines.sublist(startLine, endLine).join('\n');
  }

  String? _findFieldUsageContext(Script script, String className) {
    final lines = script.source!.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('List<$className>') ||
          (line.contains('Map<') && line.contains(className))) {
        final contextStart = (i - 5).clamp(0, lines.length - 1);
        final contextEnd = (i + 20).clamp(0, lines.length);
        debugPrint('getClassSourceLocation: Found field usage at line ${i + 1}');
        return lines.sublist(contextStart, contextEnd).join('\n');
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Source-string based helpers (for DTD fallback when VM source is unavailable)
  // ---------------------------------------------------------------------------

  int? _findClassDefinitionLineInSource(String source, String className) {
    debugPrint('_findClassDefinitionLineInSource: Searching for "class $className"');
    final lines = source.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains('class $className ') ||
          lines[i].contains('class $className{') ||
          lines[i].contains('class $className<')) {
        debugPrint('_findClassDefinitionLineInSource: Found at line ${i + 1}');
        return i + 1;
      }
    }
    return null;
  }

  String? _extractCodeSnippetFromSource(String source, int lineNumber, int numLines) {
    final lines = source.split('\n');
    final startLine = (lineNumber - 1).clamp(0, lines.length - 1);
    final endLine = (startLine + numLines).clamp(0, lines.length);
    return lines.sublist(startLine, endLine).join('\n');
  }

  String? _findFieldUsageContextInSource(String source, String className) {
    final lines = source.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('List<$className>') ||
          (line.contains('Map<') && line.contains(className))) {
        final contextStart = (i - 5).clamp(0, lines.length - 1);
        final contextEnd = (i + 20).clamp(0, lines.length);
        debugPrint('_findFieldUsageContextInSource: Found field usage at line ${i + 1}');
        return lines.sublist(contextStart, contextEnd).join('\n');
      }
    }
    return null;
  }
}
