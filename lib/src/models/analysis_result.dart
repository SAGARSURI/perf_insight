/// Models for LLM analysis results.

import 'package:flutter/foundation.dart';

/// The result of an LLM performance analysis.
class AnalysisResult {
  final DateTime timestamp;
  final String provider;
  final String model;
  final List<PerformanceIssue> issues;
  final String summary;
  final List<String> recommendations;
  final AnalysisMetrics metrics;

  AnalysisResult({
    required this.timestamp,
    required this.provider,
    required this.model,
    required this.issues,
    required this.summary,
    required this.recommendations,
    required this.metrics,
  });

  factory AnalysisResult.fromLlmResponse({
    required String provider,
    required String model,
    required Map<String, dynamic> response,
  }) {
    final issues = (response['issues'] as List<dynamic>?)
            ?.map((i) => PerformanceIssue.fromJson(i as Map<String, dynamic>))
            .toList() ??
        [];

    final recommendations =
        (response['recommendations'] as List<dynamic>?)?.cast<String>() ?? [];

    return AnalysisResult(
      timestamp: DateTime.now(),
      provider: provider,
      model: model,
      issues: issues,
      summary: response['summary'] as String? ?? 'No summary provided.',
      recommendations: recommendations,
      metrics: AnalysisMetrics.fromJson(
        response['metrics'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  /// Returns issues sorted by severity (critical first).
  List<PerformanceIssue> get sortedIssues {
    return List.from(issues)
      ..sort((a, b) => b.severity.index.compareTo(a.severity.index));
  }

  bool get hasCriticalIssues =>
      issues.any((i) => i.severity == IssueSeverity.critical);

  bool get hasHighIssues =>
      issues.any((i) => i.severity == IssueSeverity.high);
}

/// A specific performance issue identified by the LLM.
class PerformanceIssue {
  final String title;
  final String description;
  final IssueSeverity severity;
  final IssueCategory category;
  final String? affectedArea;
  final List<String> suggestedFixes;
  final String? codeExample;

  /// Source file where the issue was found (e.g., "main.dart")
  final String? sourceFile;

  /// Line number in the source file
  final int? lineNumber;

  /// Retention path showing why objects are retained
  /// e.g., ["ProductItem", "_productCatalog", "State", "Widget Tree"]
  final List<String>? retentionPath;

  PerformanceIssue({
    required this.title,
    required this.description,
    required this.severity,
    required this.category,
    this.affectedArea,
    required this.suggestedFixes,
    this.codeExample,
    this.sourceFile,
    this.lineNumber,
    this.retentionPath,
  });

  factory PerformanceIssue.fromJson(Map<String, dynamic> json) {
    return PerformanceIssue(
      title: json['title'] as String? ?? 'Unknown Issue',
      description: json['description'] as String? ?? '',
      severity: IssueSeverity.fromString(json['severity'] as String?),
      category: IssueCategory.fromString(json['category'] as String?),
      affectedArea: json['affectedArea'] as String?,
      suggestedFixes:
          (json['suggestedFixes'] as List<dynamic>?)?.cast<String>() ?? [],
      codeExample: json['codeExample'] as String?,
      sourceFile: json['sourceFile'] as String?,
      lineNumber: json['lineNumber'] as int?,
      retentionPath:
          (json['retentionPath'] as List<dynamic>?)?.cast<String>(),
    );
  }

  /// Returns the display location (e.g., "main.dart:96")
  String? get displayLocation {
    if (sourceFile == null) return null;
    if (lineNumber != null) {
      return '$sourceFile:$lineNumber';
    }
    return sourceFile;
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'severity': severity.name,
        'category': category.name,
        if (affectedArea != null) 'affectedArea': affectedArea,
        'suggestedFixes': suggestedFixes,
        if (codeExample != null) 'codeExample': codeExample,
        if (sourceFile != null) 'sourceFile': sourceFile,
        if (lineNumber != null) 'lineNumber': lineNumber,
        if (retentionPath != null) 'retentionPath': retentionPath,
      };
}

/// Severity levels for performance issues.
enum IssueSeverity {
  critical, // Immediate attention required
  high, // Should be addressed soon
  medium, // Worth investigating
  low, // Minor optimization opportunity
  info; // Informational only

  static IssueSeverity fromString(String? value) {
    return IssueSeverity.values.firstWhere(
      (s) => s.name.toLowerCase() == value?.toLowerCase(),
      orElse: () => IssueSeverity.medium,
    );
  }

  String get displayName {
    switch (this) {
      case IssueSeverity.critical:
        return 'Critical';
      case IssueSeverity.high:
        return 'High';
      case IssueSeverity.medium:
        return 'Medium';
      case IssueSeverity.low:
        return 'Low';
      case IssueSeverity.info:
        return 'Info';
    }
  }
}

/// Categories of performance issues.
enum IssueCategory {
  cpu, // CPU-bound issues
  memory, // Memory leaks, allocations
  rendering, // Frame rendering, jank
  io, // I/O blocking
  concurrency, // Isolate issues
  general; // General performance

  static IssueCategory fromString(String? value) {
    return IssueCategory.values.firstWhere(
      (c) => c.name.toLowerCase() == value?.toLowerCase(),
      orElse: () => IssueCategory.general,
    );
  }

  String get displayName {
    switch (this) {
      case IssueCategory.cpu:
        return 'CPU';
      case IssueCategory.memory:
        return 'Memory';
      case IssueCategory.rendering:
        return 'Rendering';
      case IssueCategory.io:
        return 'I/O';
      case IssueCategory.concurrency:
        return 'Concurrency';
      case IssueCategory.general:
        return 'General';
    }
  }
}

/// Metrics about the analysis itself.
class AnalysisMetrics {
  final int tokensUsed;
  final int inputTokens;
  final int outputTokens;
  final Duration responseTime;
  final String? errorMessage;

  AnalysisMetrics({
    required this.tokensUsed,
    required this.inputTokens,
    required this.outputTokens,
    required this.responseTime,
    this.errorMessage,
  });

  factory AnalysisMetrics.fromJson(Map<String, dynamic> json) {
    return AnalysisMetrics(
      tokensUsed: json['tokensUsed'] as int? ?? 0,
      inputTokens: json['inputTokens'] as int? ?? 0,
      outputTokens: json['outputTokens'] as int? ?? 0,
      responseTime: Duration(
        milliseconds: json['responseTimeMs'] as int? ?? 0,
      ),
      errorMessage: json['error'] as String?,
    );
  }

  bool get hasError => errorMessage != null;
}

/// State for tracking ongoing analysis.
enum AnalysisState {
  idle,
  collecting,
  analyzing,
  complete,
  error,
}

/// Notifier for analysis state changes.
class AnalysisStateNotifier extends ChangeNotifier {
  AnalysisState _state = AnalysisState.idle;
  String? _errorMessage;
  AnalysisResult? _result;
  double _progress = 0.0;

  AnalysisState get state => _state;
  String? get errorMessage => _errorMessage;
  AnalysisResult? get result => _result;
  double get progress => _progress;

  void setCollecting() {
    _state = AnalysisState.collecting;
    _progress = 0.25;
    _errorMessage = null;
    notifyListeners();
  }

  void setAnalyzing() {
    _state = AnalysisState.analyzing;
    _progress = 0.5;
    notifyListeners();
  }

  void setComplete(AnalysisResult result) {
    _state = AnalysisState.complete;
    _result = result;
    _progress = 1.0;
    notifyListeners();
  }

  void setError(String message) {
    _state = AnalysisState.error;
    _errorMessage = message;
    _progress = 0.0;
    notifyListeners();
  }

  void reset() {
    _state = AnalysisState.idle;
    _errorMessage = null;
    _result = null;
    _progress = 0.0;
    notifyListeners();
  }
}
