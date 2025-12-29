/// Home screen with performance analysis dashboard.

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import '../collectors/performance_collector.dart';
import '../llm/llm_provider.dart';
import '../models/analysis_result.dart';
import '../models/performance_data.dart';
import '../privacy/data_redactor.dart';
import '../widgets/analysis_panel.dart';
import '../widgets/class_detail_panel.dart';
import '../widgets/memory_treemap.dart';
import 'settings_screen.dart';

/// Main home screen for the performance analysis extension.
class HomeScreen extends StatefulWidget {
  final void Function(PerformanceSnapshot?)? onSnapshotCollected;

  const HomeScreen({super.key, this.onSnapshotCollected});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum ViewMode { overview, classDetail }

class _HomeScreenState extends State<HomeScreen> {
  PerformanceCollector? _collector;
  PerformanceSnapshot? _snapshot;

  // Debug: Store the last data sent to AI for inspection
  String? _lastAiDataDebug;
  bool _isDebugMode = false; // True if source code is available (debug build)
  AnalysisResult? _analysisResult;
  AnalysisState _analysisState = AnalysisState.idle;
  String? _errorMessage;
  bool _isConnected = false;

  // Class drill-down state
  ViewMode _viewMode = ViewMode.overview;
  AllocationSample? _selectedClass;
  bool _isLoadingClassDetails = false;
  String? _classAiInsight;

  // Race condition prevention: track selection version
  int _classSelectionVersion = 0;

  // Cache for enhanced class info to avoid re-fetching
  final Map<String, AllocationSample> _enhancedClassCache = {};

  @override
  void initState() {
    super.initState();
    _initializeCollector();
  }

  Future<void> _initializeCollector() async {
    // Wait for VM service to be available
    try {
      final vmService = await serviceManager.onServiceAvailable;
      setState(() {
        _collector = PerformanceCollector(vmService);
        _isConnected = true;
      });
      await _collector!.initialize();

      // Auto-collect initial snapshot to show data immediately
      await _collectInitialSnapshot();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to connect to VM service: $e';
        _isConnected = false;
      });
    }
  }

  /// Collect initial snapshot without AI analysis to show data immediately.
  Future<void> _collectInitialSnapshot() async {
    if (_collector == null) return;

    try {
      final snapshot = await _collector!.collectSnapshot();
      setState(() {
        _snapshot = snapshot;
      });
      widget.onSnapshotCollected?.call(snapshot);
    } catch (e) {
      debugPrint('Initial snapshot collection failed: $e');
    }
  }

  /// Enhance top user classes with retention paths and source locations.
  /// This provides the AI with exact root cause information.
  Future<PerformanceSnapshot> _enhanceTopClasses(PerformanceSnapshot snapshot) async {
    if (snapshot.memory == null || _collector == null) {
      debugPrint('=== _enhanceTopClasses: No memory data or collector ===');
      return snapshot;
    }

    // Get top 5 user classes by size
    final userClasses = snapshot.memory!.topAllocations
        .where((a) => a.isUserClass && a.classId != null)
        .take(5)
        .toList();

    debugPrint('=== _enhanceTopClasses: Found ${userClasses.length} user classes with classId ===');
    for (final c in userClasses) {
      debugPrint('  - ${c.className}: classId=${c.classId}');
    }

    if (userClasses.isEmpty) return snapshot;

    // Fetch enhanced data for each in parallel
    final enhancedClasses = await Future.wait(
      userClasses.map((allocation) async {
        try {
          debugPrint('Fetching enhanced info for ${allocation.className}...');
          final enhanced = await _collector!.getEnhancedAllocationInfo(allocation);
          debugPrint('  sourceLocation: ${enhanced?.sourceLocation?.displayPath}');
          debugPrint('  retentionInfo: ${enhanced?.retentionInfo?.pathSummary}');
          return enhanced;
        } catch (e) {
          debugPrint('  ERROR: $e');
          return allocation;
        }
      }),
    );

    // Replace the enhanced classes in the allocations list
    final updatedAllocations = snapshot.memory!.topAllocations.map((original) {
      // Find matching enhanced class (if any)
      for (final enhanced in enhancedClasses) {
        if (enhanced != null && enhanced.className == original.className) {
          return enhanced;
        }
      }
      return original;
    }).toList();

    // Log what we got
    debugPrint('=== Enhanced allocations summary ===');
    for (final a in updatedAllocations.where((a) => a.isUserClass).take(5)) {
      debugPrint('${a.className}: srcLoc=${a.sourceLocation?.displayPath}, retention=${a.retentionInfo?.pathSummary}');
    }

    // Create updated memory data
    final updatedMemory = MemoryData(
      usedHeapSize: snapshot.memory!.usedHeapSize,
      heapCapacity: snapshot.memory!.heapCapacity,
      externalUsage: snapshot.memory!.externalUsage,
      gcCount: snapshot.memory!.gcCount,
      topAllocations: updatedAllocations,
    );

    // Enhance CPU data with source locations for jank analysis
    CpuData? enhancedCpu = snapshot.cpu;
    if (snapshot.cpu != null) {
      debugPrint('=== Enhancing CPU data for jank analysis ===');
      final userFunctions = snapshot.cpu!.topFunctions
          .where((f) => f.isUserFunction && f.functionId != null)
          .take(5)
          .toList();
      debugPrint('Found ${userFunctions.length} user functions to enhance');

      if (userFunctions.isNotEmpty) {
        try {
          enhancedCpu = await _collector!.getEnhancedCpuData(snapshot.cpu!);
          // Log what we got
          for (final f in enhancedCpu!.topFunctions.where((f) => f.isUserFunction).take(5)) {
            debugPrint('  ${f.functionName}: srcLoc=${f.sourceLocation?.displayPath}');
          }
        } catch (e) {
          debugPrint('Error enhancing CPU data: $e');
        }
      }
    }

    return PerformanceSnapshot(
      timestamp: snapshot.timestamp,
      isolateId: snapshot.isolateId,
      cpu: enhancedCpu,
      memory: updatedMemory,
      timeline: snapshot.timeline,
    );
  }

  Future<void> _collectAndAnalyze() async {
    if (_collector == null) {
      setState(() {
        _errorMessage = 'Not connected to a running application.';
      });
      return;
    }

    // Load settings
    final config = await SettingsLoader.loadActiveConfig();
    if (config == null) {
      setState(() {
        _errorMessage = 'Please configure your API key in settings.';
        _analysisState = AnalysisState.error;
      });
      return;
    }

    setState(() {
      _analysisState = AnalysisState.collecting;
      _errorMessage = null;
    });

    try {
      // Collect performance data
      final snapshot = await _collector!.collectSnapshot();

      setState(() {
        _snapshot = snapshot;
        _analysisState = AnalysisState.analyzing;
      });

      // Notify parent about the snapshot
      widget.onSnapshotCollected?.call(snapshot);

      // Fetch enhanced data (retention paths, source locations) for top user classes
      // This gives the AI the exact root cause information
      final enhancedSnapshot = await _enhanceTopClasses(snapshot);

      // Check if we're in debug mode (source code available)
      // by checking if any allocation has a codeSnippet
      final hasSourceCode = enhancedSnapshot.memory?.topAllocations
          .any((a) => a.sourceLocation?.codeSnippet != null) ?? false;
      _isDebugMode = hasSourceCode;

      // Redact data based on privacy settings
      final privacyLevel = await SettingsLoader.loadPrivacyLevel();
      final redactor = DataRedactor(level: privacyLevel);
      final analysisData = redactor.createEnhancedAnalysisSummary(enhancedSnapshot);

      // Debug: Log the data being sent to AI and store for UI inspection
      final debugBuffer = StringBuffer();
      debugBuffer.writeln('=== DATA BEING SENT TO AI ===');
      debugBuffer.writeln('Privacy level: $privacyLevel');
      final appClasses = (analysisData['memory'] as Map<String, dynamic>?)?['appClasses'] as List?;
      if (appClasses != null && appClasses.isNotEmpty) {
        debugBuffer.writeln('Found ${appClasses.length} app classes:');
        for (final cls in appClasses.take(5)) {
          final classData = cls as Map<String, dynamic>;
          final codeSnippet = classData['codeSnippet'] as String?;
          final usageContext = classData['usageContext'] as String?;
          debugBuffer.writeln('  ${classData['className']}:');
          debugBuffer.writeln('    sourceLocation: ${classData['sourceLocation'] ?? 'NULL'}');
          debugBuffer.writeln('    retentionPath: ${classData['retentionPath'] ?? 'NULL'}');
          debugBuffer.writeln('    rootType: ${classData['rootType'] ?? 'NULL'}');
          debugBuffer.writeln('    codeSnippet: ${codeSnippet != null ? '${codeSnippet.length} chars' : 'NULL'}');
          debugBuffer.writeln('    usageContext: ${usageContext != null ? '${usageContext.length} chars' : 'NULL'}');
        }
      } else {
        debugBuffer.writeln('WARNING: No appClasses in analysisData!');
        debugBuffer.writeln('Memory data: ${analysisData['memory']}');
      }

      // Log CPU hotspots data
      final appFunctions = (analysisData['cpu'] as Map<String, dynamic>?)?['appFunctions'] as List?;
      if (appFunctions != null && appFunctions.isNotEmpty) {
        debugBuffer.writeln('Found ${appFunctions.length} app functions (CPU hotspots):');
        for (final func in appFunctions.take(5)) {
          final funcData = func as Map<String, dynamic>;
          final codeSnippet = funcData['codeSnippet'] as String?;
          debugBuffer.writeln('  ${funcData['functionName']}:');
          debugBuffer.writeln('    className: ${funcData['className'] ?? 'N/A'}');
          debugBuffer.writeln('    percentage: ${funcData['percentage']}%');
          debugBuffer.writeln('    sourceLocation: ${funcData['sourceLocation'] ?? 'NULL'}');
          debugBuffer.writeln('    codeSnippet: ${codeSnippet != null ? '${codeSnippet.length} chars' : 'NULL'}');
        }
      } else {
        debugBuffer.writeln('No appFunctions (CPU hotspots) in analysisData');
      }

      debugBuffer.writeln('=== END DATA ===');
      setState(() {
        _lastAiDataDebug = debugBuffer.toString();
      });
      debugPrint(_lastAiDataDebug!);

      // Send to LLM for analysis
      final provider = LlmProvider.create(config);
      final result = await provider.analyzePerformance(analysisData);

      setState(() {
        _analysisResult = result;
        _analysisState = AnalysisState.complete;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _analysisState = AnalysisState.error;
      });
    }
  }

  void _reset() {
    // Clear the cache when resetting
    _enhancedClassCache.clear();
    _classSelectionVersion++;

    setState(() {
      _snapshot = null;
      _analysisResult = null;
      _analysisState = AnalysisState.idle;
      _errorMessage = null;
      _viewMode = ViewMode.overview;
      _selectedClass = null;
      _classAiInsight = null;
    });
  }

  /// Handle class selection from the treemap.
  Future<void> _onClassSelected(AllocationSample allocation) async {
    // Increment version to invalidate any in-flight requests
    final currentVersion = ++_classSelectionVersion;

    // Check cache first
    final cacheKey = allocation.classId ?? allocation.className;
    final cached = _enhancedClassCache[cacheKey];

    setState(() {
      _selectedClass = cached ?? allocation;
      _viewMode = ViewMode.classDetail;
      _isLoadingClassDetails = cached == null;
      _classAiInsight = null;
    });

    // If we have cached data, no need to fetch
    if (cached != null) return;

    // Load enhanced details (source location, retention path)
    if (_collector != null && allocation.classId != null) {
      try {
        final enhanced = await _collector!.getEnhancedAllocationInfo(allocation);

        // Check if this request is still valid (user hasn't selected another class)
        if (!mounted || currentVersion != _classSelectionVersion) return;

        // Cache the enhanced data
        if (enhanced != null) {
          _enhancedClassCache[cacheKey] = enhanced;
        }

        setState(() {
          _selectedClass = enhanced ?? allocation;
          _isLoadingClassDetails = false;
        });
      } catch (e) {
        // Check if this request is still valid
        if (!mounted || currentVersion != _classSelectionVersion) return;

        setState(() {
          _isLoadingClassDetails = false;
        });
      }
    } else {
      setState(() {
        _isLoadingClassDetails = false;
      });
    }
  }

  /// Request AI analysis for the selected class.
  Future<void> _requestClassAiAnalysis() async {
    if (_selectedClass == null) return;

    final config = await SettingsLoader.loadActiveConfig();
    if (config == null) {
      setState(() {
        _classAiInsight = 'Please configure your API key in settings.';
      });
      return;
    }

    setState(() {
      _isLoadingClassDetails = true;
    });

    try {
      final provider = LlmProvider.create(config);

      // Build context with class details
      final classContext = {
        'className': _selectedClass!.className,
        'instanceCount': _selectedClass!.instanceCount,
        'totalBytes': _selectedClass!.totalBytes,
        'isUserClass': _selectedClass!.isUserClass,
        if (_selectedClass!.sourceLocation != null)
          'sourceLocation': _selectedClass!.sourceLocation!.toJson(),
        if (_selectedClass!.retentionInfo != null)
          'retentionPath': _selectedClass!.retentionInfo!.toJson(),
      };

      final result = await provider.analyzeClass(classContext);

      if (mounted) {
        setState(() {
          _classAiInsight = result;
          _isLoadingClassDetails = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _classAiInsight = 'Error: $e';
          _isLoadingClassDetails = false;
        });
      }
    }
  }

  /// Go back to overview from class detail.
  void _backToOverview() {
    setState(() {
      _viewMode = ViewMode.overview;
      _selectedClass = null;
      _classAiInsight = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Left panel - Controls and metrics
          Expanded(
            flex: 2,
            child: _buildControlPanel(),
          ),
          const VerticalDivider(width: 1),
          // Right panel - Analysis results
          Expanded(
            flex: 3,
            child: _buildAnalysisPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildConnectionStatus(),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: _buildAnalyzeButton(),
        ),
        const Divider(height: 1),
        Expanded(
          child: _snapshot != null
              ? _buildMemoryExplorer()
              : _buildEmptyState(),
        ),
      ],
    );
  }

  /// New: Memory Explorer with treemap and class details.
  Widget _buildMemoryExplorer() {
    if (_snapshot?.memory == null) {
      return Center(
        child: Text(
          'No memory data available',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _viewMode == ViewMode.classDetail && _selectedClass != null
          ? _buildClassDetailView()
          : _buildOverviewView(),
    );
  }

  Widget _buildOverviewView() {
    return SingleChildScrollView(
      key: const ValueKey('overview'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Memory Treemap - Main focus on heap allocation analysis
          MemoryTreemap(
            memory: _snapshot!.memory!,
            onClassSelected: _onClassSelected,
            selectedClass: _selectedClass,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  Widget _buildClassDetailView() {
    return SingleChildScrollView(
      key: const ValueKey('detail'),
      padding: const EdgeInsets.all(16),
      child: ClassDetailPanel(
        allocation: _selectedClass!,
        isLoading: _isLoadingClassDetails,
        aiInsight: _classAiInsight,
        onClose: _backToOverview,
        onRequestAiAnalysis: _requestClassAiAnalysis,
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: _isConnected
          ? Colors.green.withOpacity(0.1)
          : Colors.orange.withOpacity(0.1),
      child: Row(
        children: [
          Icon(
            _isConnected ? Icons.check_circle : Icons.warning,
            size: 16,
            color: _isConnected ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isConnected
                  ? 'Connected to running application'
                  : 'Waiting for application connection...',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  bool _isRefreshing = false;

  /// Refresh memory data without running AI analysis.
  Future<void> _refreshData() async {
    if (_collector == null || _isRefreshing) return;

    // Clear cache since we're getting fresh data
    _enhancedClassCache.clear();
    _classSelectionVersion++;

    setState(() {
      _isRefreshing = true;
    });

    try {
      final snapshot = await _collector!.collectSnapshot();
      setState(() {
        _snapshot = snapshot;
        _isRefreshing = false;
      });
      widget.onSnapshotCollected?.call(snapshot);
    } catch (e) {
      setState(() {
        _isRefreshing = false;
      });
      debugPrint('Refresh failed: $e');
    }
  }

  Widget _buildAnalyzeButton() {
    final isLoading = _analysisState == AnalysisState.collecting ||
        _analysisState == AnalysisState.analyzing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: isLoading ? null : _collectAndAnalyze,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.analytics),
                label: Text(_getButtonLabel()),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 40,
              child: OutlinedButton(
                onPressed: _isRefreshing ? null : _refreshData,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: _isRefreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 20),
              ),
            ),
          ],
        ),
        if (_analysisResult != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('New Analysis'),
          ),
        ],
      ],
    );
  }

  String _getButtonLabel() {
    switch (_analysisState) {
      case AnalysisState.idle:
        return 'Analyze Performance';
      case AnalysisState.collecting:
        return 'Collecting Data...';
      case AnalysisState.analyzing:
        return 'Analyzing with AI...';
      case AnalysisState.complete:
        return 'Analysis Complete';
      case AnalysisState.error:
        return 'Retry Analysis';
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.speed,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Performance AI Insights',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Click "Analyze Performance" to collect metrics\nand get AI-powered insights.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisPanel() {
    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_analysisResult != null) {
      return AnalysisPanel(
        result: _analysisResult!,
        // Only show debug info in debug mode (when source code is available)
        debugInfo: _isDebugMode ? _lastAiDataDebug : null,
      );
    }

    if (_analysisState == AnalysisState.analyzing) {
      return _buildAnalyzingState();
    }

    return _buildWaitingState();
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Analysis Error',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                // Navigate to settings
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => SettingsScreen(
                      onSettingsSaved: () => Navigator.of(context).pop(),
                    ),
                  ),
                );
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyzingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            'Analyzing with AI...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'This may take a few seconds.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lightbulb_outline,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'AI Analysis',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Analysis results will appear here.\nStart by clicking "Analyze Performance".',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
