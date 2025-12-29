/// Service for fetching source code from the connected app's codebase.
///
/// Uses DTD (Dart Tooling Daemon) as primary source for reliable file access,
/// with VM Service Script.source as fallback.

import 'dart:async';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:dtd/dtd.dart'; // For FileSystemService extension
import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

import '../models/performance_data.dart';

/// Configuration for CodeContextService limits and timeouts.
class CodeContextConfig {
  /// Maximum number of scripts to search in VM Service fallback.
  static const int maxScriptsToSearch = 100;

  /// Maximum depth for recursive directory traversal.
  static const int maxDirectoryDepth = 10;

  /// Maximum number of Dart files to process.
  static const int maxDartFiles = 500;

  /// Maximum cache size before eviction.
  static const int maxCacheSize = 200;

  /// Timeout for VM service calls in milliseconds.
  static const int vmServiceTimeoutMs = 5000;

  /// Directories to skip during traversal.
  static const Set<String> skipDirectories = {
    '.dart_tool',
    'build',
    '.git',
    'node_modules',
    '.pub-cache',
    '.pub',
    'ios',
    'android',
    'macos',
    'windows',
    'linux',
    'web',
  };
}

/// Represents a usage of a class in the codebase.
class ClassUsage {
  final String filePath;
  final int lineNumber;
  final String lineContent;
  final String context; // Surrounding code

  ClassUsage({
    required this.filePath,
    required this.lineNumber,
    required this.lineContent,
    required this.context,
  });

  Map<String, dynamic> toJson() => {
        'file': filePath,
        'line': lineNumber,
        'content': lineContent,
        'context': context,
      };
}

/// Complete code context for AI analysis.
class CodeContext {
  final String className;
  final String? filePath;
  final int? lineNumber;
  final String? classDefinition; // Full class source code
  final List<ClassUsage> usages; // Where it's used
  final String? fullFileSource; // Entire file for reference

  CodeContext({
    required this.className,
    this.filePath,
    this.lineNumber,
    this.classDefinition,
    required this.usages,
    this.fullFileSource,
  });

  /// Summary for LLM context.
  Map<String, dynamic> toJson() => {
        'className': className,
        if (filePath != null) 'filePath': filePath,
        if (lineNumber != null) 'lineNumber': lineNumber,
        if (classDefinition != null) 'classDefinition': classDefinition,
        'usageCount': usages.length,
        'usages': usages.take(5).map((u) => u.toJson()).toList(),
      };
}

/// Service for fetching source code from the connected app's codebase.
///
/// Uses DTD (Dart Tooling Daemon) as primary source, VM Service as fallback.
/// DTD provides direct file system access which is more reliable than
/// VM Service's Script.source (which can be null for some scripts).
class CodeContextService {
  final VmService _vmService;

  // LRU Cache: file path → source code (with access order tracking)
  final Map<String, String> _sourceCache = {};
  final List<String> _sourceCacheOrder = []; // Track access order for LRU

  // Cache: package URI → file path
  final Map<String, String> _packageToFileMap = {};

  // Project root URI (cached)
  Uri? _projectRoot;

  CodeContextService(this._vmService);

  /// Add to cache with LRU eviction.
  void _addToSourceCache(String key, String value) {
    // Remove if already exists (will be re-added at end)
    if (_sourceCache.containsKey(key)) {
      _sourceCacheOrder.remove(key);
    }

    // Evict oldest entries if cache is full
    while (_sourceCache.length >= CodeContextConfig.maxCacheSize) {
      if (_sourceCacheOrder.isEmpty) break;
      final oldest = _sourceCacheOrder.removeAt(0);
      _sourceCache.remove(oldest);
      debugPrint('CodeContext: Evicted cache entry: $oldest');
    }

    _sourceCache[key] = value;
    _sourceCacheOrder.add(key);
  }

  /// Get from cache and update access order.
  String? _getFromSourceCache(String key) {
    if (_sourceCache.containsKey(key)) {
      // Move to end (most recently used)
      _sourceCacheOrder.remove(key);
      _sourceCacheOrder.add(key);
      return _sourceCache[key];
    }
    return null;
  }

  /// Check if DTD is available for file access.
  bool get isDtdAvailable {
    try {
      return dtdManager.hasConnection;
    } catch (e) {
      // dtdManager not initialized (not in DevToolsExtension context)
      return false;
    }
  }

  /// Clear all caches.
  void clearCache() {
    _sourceCache.clear();
    _sourceCacheOrder.clear();
    _packageToFileMap.clear();
    _projectRoot = null;
  }

  /// Get the project root directory.
  Future<Uri?> getProjectRoot() async {
    if (_projectRoot != null) return _projectRoot;

    if (!isDtdAvailable) return null;

    try {
      final workspaceRoots = await dtdManager.workspaceRoots();
      if (workspaceRoots != null) {
        debugPrint('CodeContext: IDE Workspace Roots = ${workspaceRoots.ideWorkspaceRoots}');
        if (workspaceRoots.ideWorkspaceRoots.isNotEmpty) {
          _projectRoot = workspaceRoots.ideWorkspaceRoots.first;
          debugPrint('CodeContext: Using project root = $_projectRoot');
          return _projectRoot;
        }
      }
    } catch (e) {
      debugPrint('CodeContext: Failed to get project root: $e');
    }

    return null;
  }

  /// Get source code for a file.
  ///
  /// Tries DTD first (most reliable), falls back to VM Service.
  /// Uses LRU cache to avoid repeated reads.
  Future<String?> getFileSource(String filePath) async {
    // Check LRU cache first
    final cached = _getFromSourceCache(filePath);
    if (cached != null) {
      return cached;
    }

    // Normalize the path
    final normalizedPath = _normalizeFilePath(filePath);

    // Try DTD (most reliable) with timeout
    if (isDtdAvailable) {
      try {
        final uri = await _resolveFileUri(normalizedPath);
        if (uri != null) {
          final daemon = dtdManager.connection.value;
          if (daemon != null) {
            final fileContent = await daemon
                .readFileAsString(uri)
                .timeout(Duration(milliseconds: CodeContextConfig.vmServiceTimeoutMs));
            final source = fileContent.content;
            if (source != null) {
              _addToSourceCache(filePath, source);
              debugPrint('CodeContext: DTD read ${source.length} chars from $normalizedPath');
              return source;
            }
          }
        }
      } on TimeoutException {
        debugPrint('CodeContext: DTD read timed out for $normalizedPath');
      } catch (e) {
        debugPrint('CodeContext: DTD read failed for $normalizedPath: $e');
      }
    }

    // Fallback to VM Service
    return _getSourceFromVmService(filePath);
  }

  /// List all Dart files in a directory.
  ///
  /// Parameters:
  /// - [directory] - The directory to search (relative to project root)
  /// - [depth] - Current recursion depth (internal use)
  /// - [fileCount] - Running count of files found (internal use)
  Future<List<String>> listDartFiles(
    String directory, {
    int depth = 0,
    int fileCount = 0,
  }) async {
    if (!isDtdAvailable) return [];

    // Enforce depth limit to prevent stack overflow
    if (depth > CodeContextConfig.maxDirectoryDepth) {
      debugPrint('CodeContext: Max depth reached at $directory');
      return [];
    }

    try {
      final projectRoot = await getProjectRoot();
      if (projectRoot == null) return [];

      // Ensure project root has trailing slash for proper resolution
      final rootWithSlash = projectRoot.path.endsWith('/')
          ? projectRoot
          : Uri.parse('${projectRoot.toString()}/');
      final dirUri = rootWithSlash.resolve(directory);
      debugPrint('CodeContext: Listing directory (depth=$depth): $dirUri');

      final daemon = dtdManager.connection.value;
      if (daemon == null) return [];

      final contents = await daemon
          .listDirectoryContents(dirUri)
          .timeout(Duration(milliseconds: CodeContextConfig.vmServiceTimeoutMs));
      final dartFiles = <String>[];

      final uris = contents.uris;
      if (uris == null) return [];

      int currentFileCount = fileCount;

      for (final item in uris) {
        // Enforce file limit
        if (currentFileCount >= CodeContextConfig.maxDartFiles) {
          debugPrint('CodeContext: Max file limit reached ($currentFileCount files)');
          break;
        }

        final path = item.path;
        final lastSegment = item.pathSegments.isNotEmpty ? item.pathSegments.last : '';

        // Skip known non-source directories
        if (CodeContextConfig.skipDirectories.contains(lastSegment)) {
          continue;
        }

        if (path.endsWith('.dart')) {
          dartFiles.add(path);
          currentFileCount++;
        }

        // Check if this is a directory by looking at the last segment only
        final isLikelyDirectory = lastSegment.isNotEmpty &&
            !lastSegment.contains('.') &&
            !path.endsWith('/');

        if (isLikelyDirectory) {
          try {
            final subFiles = await listDartFiles(
              '$directory/$lastSegment',
              depth: depth + 1,
              fileCount: currentFileCount,
            );
            dartFiles.addAll(subFiles);
            currentFileCount += subFiles.length;
          } catch (e) {
            // Log the error instead of silently swallowing
            debugPrint('CodeContext: Could not list subdirectory $lastSegment: $e');
          }
        }
      }

      return dartFiles;
    } on TimeoutException {
      debugPrint('CodeContext: Timeout listing directory $directory');
      return [];
    } catch (e) {
      debugPrint('CodeContext: Failed to list files in $directory: $e');
      return [];
    }
  }

  /// Find all files that reference a given class name.
  Future<List<ClassUsage>> findClassUsages(String className) async {
    final usages = <ClassUsage>[];

    // Log DTD status for debugging
    debugPrint('CodeContext: Finding usages for $className');
    debugPrint('CodeContext: DTD available = $isDtdAvailable');
    if (isDtdAvailable) {
      final root = await getProjectRoot();
      debugPrint('CodeContext: Project root = $root');
    }

    // First try to get files via DTD
    final dartFiles = await listDartFiles('lib/');
    debugPrint('CodeContext: DTD found ${dartFiles.length} dart files');

    if (dartFiles.isNotEmpty) {
      // Use DTD file list
      for (final file in dartFiles) {
        final source = await getFileSource(file);
        if (source == null) continue;
        _findUsagesInSource(source, className, file, usages);
      }
    } else {
      // Fallback: Use VM Service scripts when DTD isn't available
      debugPrint('CodeContext: DTD not available, falling back to VM Service scripts');
      await _findUsagesFromVmServiceScripts(className, usages);
    }

    debugPrint('CodeContext: Found ${usages.length} usages of $className');
    return usages;
  }

  /// Search for class usages in source code.
  void _findUsagesInSource(
    String source,
    String className,
    String filePath,
    List<ClassUsage> usages,
  ) {
    final lines = source.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains(className) &&
          !line.contains('class $className') &&
          !line.trimLeft().startsWith('//') &&
          !line.trimLeft().startsWith('import ')) {
        usages.add(ClassUsage(
          filePath: filePath,
          lineNumber: i + 1,
          lineContent: line.trim(),
          context: _extractContext(lines, i, 5, 10),
        ));
      }
    }
  }

  /// Find usages by searching VM Service scripts (fallback when DTD unavailable).
  ///
  /// This method is limited to [CodeContextConfig.maxScriptsToSearch] scripts
  /// to prevent performance issues in large apps.
  Future<void> _findUsagesFromVmServiceScripts(
    String className,
    List<ClassUsage> usages,
  ) async {
    try {
      final vm = await _vmService
          .getVM()
          .timeout(Duration(milliseconds: CodeContextConfig.vmServiceTimeoutMs));
      final isolates = vm.isolates ?? [];
      if (isolates.isEmpty) {
        debugPrint('CodeContext: No isolates found for VM script search');
        return;
      }

      final isolateId = isolates.first.id!;
      final scripts = await _vmService
          .getScripts(isolateId)
          .timeout(Duration(milliseconds: CodeContextConfig.vmServiceTimeoutMs));
      final scriptList = scripts.scripts ?? [];

      debugPrint('CodeContext: VM returned ${scriptList.length} scripts total');

      // Filter to user scripts only
      final userScripts = scriptList.where((scriptRef) {
        final uri = scriptRef.uri ?? '';

        // Skip internal Dart packages
        if (uri.startsWith('dart:')) return false;

        // Skip common framework packages
        if (_isFrameworkPackage(uri)) return false;

        // Only include package: URIs (user's app packages) or file: URIs with /lib/
        final isUserPackage = uri.startsWith('package:');
        final isUserFile = uri.startsWith('file:') && uri.contains('/lib/');
        return isUserPackage || isUserFile;
      }).take(CodeContextConfig.maxScriptsToSearch).toList();

      debugPrint('CodeContext: Filtered to ${userScripts.length} user scripts (limit: ${CodeContextConfig.maxScriptsToSearch})');

      int scriptsSearched = 0;
      int scriptsWithNullSource = 0;

      for (final scriptRef in userScripts) {
        final uri = scriptRef.uri ?? '';

        try {
          final script = await _vmService
              .getObject(isolateId, scriptRef.id!)
              .timeout(Duration(milliseconds: CodeContextConfig.vmServiceTimeoutMs));

          if (script is Script) {
            if (script.source != null) {
              scriptsSearched++;
              _findUsagesInSource(script.source!, className, uri, usages);
              // Cache the source for later use (using LRU cache)
              _addToSourceCache(uri, script.source!);
            } else {
              scriptsWithNullSource++;
              if (scriptsWithNullSource <= 3) {
                debugPrint('CodeContext: Script.source is NULL for $uri (profile mode)');
              }
            }
          }
        } on TimeoutException {
          debugPrint('CodeContext: Timeout reading script $uri');
        } catch (e) {
          debugPrint('CodeContext: Could not read script $uri: $e');
        }
      }

      debugPrint('CodeContext: Searched $scriptsSearched scripts, $scriptsWithNullSource had NULL source');
    } on TimeoutException {
      debugPrint('CodeContext: VM script search timed out');
    } catch (e) {
      debugPrint('CodeContext: VM script search failed: $e');
    }
  }

  /// Check if a package URI is a framework/dependency (not user code).
  bool _isFrameworkPackage(String uri) {
    // Common framework and dependency prefixes
    const frameworkPrefixes = [
      'package:flutter/',
      'package:cupertino_icons/',
      'package:flutter_riverpod/',
      'package:riverpod/',
      'package:shared_preferences/',
      'package:http/',
      'package:fl_chart/',
      'package:devtools_extensions/',
      'package:devtools_app_shared/',
      'package:vm_service/',
      'package:dtd/',
      'package:json_annotation/',
      'package:url_launcher',
      'package:material_color_utilities/',
      'package:collection/',
      'package:meta/',
      'package:vector_math/',
      'package:path/',
      'package:async/',
      'package:characters/',
      'package:typed_data/',
      'package:intl/',
      'package:provider/',
      'package:bloc/',
      'package:flutter_bloc/',
      'package:get/',
      'package:dio/',
      'package:retrofit/',
      'package:freezed/',
      'package:equatable/',
      'package:dartz/',
    ];

    for (final prefix in frameworkPrefixes) {
      if (uri.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }

  /// Get comprehensive code context for a class.
  Future<CodeContext> getClassContext(
    String className,
    String? isolateId,
    String? classId,
  ) async {
    // 1. Try to get class definition from VM Service (has accurate line numbers)
    CodeLocation? definition;
    String? sourceFromVm;

    if (isolateId != null && classId != null) {
      final result = await _getClassDefinitionFromVm(isolateId, classId);
      definition = result.location;
      sourceFromVm = result.source;
    }

    // 2. Get full source file via DTD (more reliable)
    String? fullSource;
    if (definition?.filePath != null) {
      fullSource = await getFileSource(definition!.filePath);
    }

    // Use VM source if DTD failed
    fullSource ??= sourceFromVm;

    // 3. Find all usages across codebase
    final usages = await findClassUsages(className);

    // 4. Extract the class definition code
    String? classCode;
    if (fullSource != null) {
      if (definition?.lineNumber != null) {
        classCode = _extractClassDefinition(fullSource, className, definition!.lineNumber!);
      } else {
        // Search for class in source
        classCode = _findAndExtractClass(fullSource, className);
      }
    }

    debugPrint('CodeContext: Built context for $className - '
        'definition: ${classCode != null}, usages: ${usages.length}');

    return CodeContext(
      className: className,
      filePath: definition?.filePath,
      lineNumber: definition?.lineNumber,
      classDefinition: classCode,
      usages: usages,
      fullFileSource: fullSource,
    );
  }

  // ===========================================================================
  // Private helpers
  // ===========================================================================

  String _normalizeFilePath(String path) {
    // Remove package: prefix for file resolution
    if (path.startsWith('package:')) {
      final parts = path.split('/');
      if (parts.length > 1) {
        // package:example_app/main.dart -> lib/main.dart
        return 'lib/${parts.sublist(1).join('/')}';
      }
    }
    return path;
  }

  Future<Uri?> _resolveFileUri(String path) async {
    final projectRoot = await getProjectRoot();
    if (projectRoot == null) return null;

    if (path.startsWith('/')) {
      return Uri.file(path);
    }

    // Ensure project root has trailing slash for proper resolution
    final rootWithSlash = projectRoot.path.endsWith('/')
        ? projectRoot
        : Uri.parse('${projectRoot.toString()}/');

    return rootWithSlash.resolve(path);
  }

  Future<String?> _getSourceFromVmService(String filePath) async {
    try {
      final vm = await _vmService.getVM();
      final isolates = vm.isolates ?? [];
      if (isolates.isEmpty) return null;

      final isolateId = isolates.first.id!;
      final scripts = await _vmService.getScripts(isolateId);

      for (final scriptRef in scripts.scripts ?? []) {
        if (scriptRef.uri?.contains(filePath) ?? false) {
          final script = await _vmService.getObject(isolateId, scriptRef.id!);
          if (script is Script && script.source != null) {
            _sourceCache[filePath] = script.source!;
            debugPrint('CodeContext: VM Service read ${script.source!.length} chars from $filePath');
            return script.source;
          }
        }
      }
    } catch (e) {
      debugPrint('CodeContext: VM Service read failed for $filePath: $e');
    }
    return null;
  }

  Future<({CodeLocation? location, String? source})> _getClassDefinitionFromVm(
    String isolateId,
    String classId,
  ) async {
    try {
      final classObj = await _vmService.getObject(isolateId, classId);

      if (classObj is! Class) {
        return (location: null, source: null);
      }

      final location = classObj.location;
      if (location == null) {
        return (location: null, source: null);
      }

      final scriptRef = location.script;
      if (scriptRef?.uri == null) {
        return (location: null, source: null);
      }

      final script = await _vmService.getObject(isolateId, scriptRef!.id!);
      String? source;
      int? lineNumber;

      if (script is Script) {
        source = script.source;

        // Get line number
        if (location.line != null && location.line! > 0) {
          lineNumber = location.line;
        } else if (source != null) {
          lineNumber = _findClassLine(source, classObj.name ?? '');
        }
      }

      return (
        location: CodeLocation(
          filePath: scriptRef.uri!,
          lineNumber: lineNumber,
          className: classObj.name,
        ),
        source: source,
      );
    } catch (e) {
      debugPrint('CodeContext: Failed to get class definition from VM: $e');
      return (location: null, source: null);
    }
  }

  int? _findClassLine(String source, String className) {
    final lines = source.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains('class $className ') ||
          lines[i].contains('class $className{') ||
          lines[i].contains('class $className<')) {
        return i + 1;
      }
    }
    return null;
  }

  String _extractContext(List<String> lines, int centerLine, int before, int after) {
    final start = (centerLine - before).clamp(0, lines.length);
    final end = (centerLine + after + 1).clamp(0, lines.length);
    return lines.sublist(start, end).join('\n');
  }

  String? _extractClassDefinition(String source, String className, int startLine) {
    final lines = source.split('\n');
    final startIdx = startLine - 1;
    if (startIdx >= lines.length || startIdx < 0) return null;

    // Find class end by counting braces
    int braceCount = 0;
    int endIdx = startIdx;
    bool foundStart = false;

    for (int i = startIdx; i < lines.length; i++) {
      final line = lines[i];
      for (final char in line.split('')) {
        if (char == '{') {
          braceCount++;
          foundStart = true;
        } else if (char == '}') {
          braceCount--;
        }
      }
      if (foundStart && braceCount == 0) {
        endIdx = i;
        break;
      }
      // Safety limit
      if (i - startIdx > 500) {
        endIdx = i;
        break;
      }
    }

    return lines.sublist(startIdx, endIdx + 1).join('\n');
  }

  String? _findAndExtractClass(String source, String className) {
    final lineNumber = _findClassLine(source, className);
    if (lineNumber == null) return null;
    return _extractClassDefinition(source, className, lineNumber);
  }
}
