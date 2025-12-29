/// LLM provider interface using direct HTTP calls.
///
/// Provides a unified interface for different LLM providers
/// (Claude, OpenAI, Gemini) with streaming support.
///
/// Note: Browser CORS restrictions may prevent direct API calls.
/// Consider using Google Gemini which has better browser support.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/analysis_result.dart';

/// Supported LLM providers.
enum LlmProviderType {
  claude,
  openai,
  gemini,
}

/// Configuration for an LLM provider.
class LlmConfig {
  final LlmProviderType type;
  final String apiKey;
  final String? model;
  final double? temperature;
  final int? maxTokens;
  final String? corsProxyUrl;

  const LlmConfig({
    required this.type,
    required this.apiKey,
    this.model,
    this.temperature,
    this.maxTokens,
    this.corsProxyUrl,
  });

  /// Wraps a URL through the CORS proxy if configured.
  ///
  /// For local-cors-proxy style:
  ///   Proxy URL: http://localhost:8010/proxy
  ///   Target: https://api.anthropic.com/v1/messages
  ///   Result: http://localhost:8010/proxy/v1/messages
  Uri proxyUrl(String url) {
    if (corsProxyUrl == null || corsProxyUrl!.isEmpty) {
      return Uri.parse(url);
    }

    final targetUri = Uri.parse(url);

    // Remove trailing slash from proxy URL if present
    final proxyBase = corsProxyUrl!.endsWith('/')
        ? corsProxyUrl!.substring(0, corsProxyUrl!.length - 1)
        : corsProxyUrl!;

    // Combine proxy base with target path
    // e.g., http://localhost:8010/proxy + /v1/messages
    return Uri.parse('$proxyBase${targetUri.path}');
  }

  String get providerName {
    switch (type) {
      case LlmProviderType.claude:
        return 'Claude';
      case LlmProviderType.openai:
        return 'OpenAI';
      case LlmProviderType.gemini:
        return 'Gemini';
    }
  }

  String get defaultModel {
    switch (type) {
      case LlmProviderType.claude:
        return 'claude-sonnet-4-20250514';
      case LlmProviderType.openai:
        return 'gpt-4o';
      case LlmProviderType.gemini:
        return 'gemini-1.5-flash';
    }
  }

  String get effectiveModel => model ?? defaultModel;
}

/// Chat message for conversation history.
class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;

  ChatMessage({required this.role, required this.content});

  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// The system prompt for memory/heap analysis.
const String performanceAnalysisPrompt = '''
You are an expert Dart and Flutter memory analyst specializing in heap allocation and memory leak detection.

CRITICAL: The data contains REAL SOURCE CODE from the user's codebase. You MUST:
1. Reference actual class names, file paths, and line numbers in your suggestions
2. Quote actual code from codeSnippet/usageContext/codebaseUsages fields
3. Provide fixes that modify the ACTUAL code shown, not generic examples
4. NEVER give generic advice - always tie it to specific code from the data
5. NEVER invent class names like "ApiCache" - ONLY use class names from the data

=== MEMORY DATA STRUCTURE ===
For each appClass in the data:
- "className" = the EXACT class name to use in ALL suggestions (NEVER substitute with other names)
- "instances" = number of live instances in memory
- "bytesKB" = total memory used by this class
- "sourceLocation" = exact file:line where class is defined
- "codeSnippet" = actual class definition code (the class itself)
- "usageContext" = THE STATE CLASS CODE showing where List<T> fields are defined
- "retentionPath" = array showing WHY objects are retained (field names like "_eventLog@xxx")
- "rootType" = what's keeping objects alive ("Widget Tree", "Static Field", "Isolate")
- "codebaseUsages" = WHERE this class is INSTANTIATED/USED in the codebase (file, line, code context)
- "codeContextAvailable" = true if we have source code access for this class

=== HOW TO IDENTIFY ROOT CAUSE ===
1. Look at "retentionPath" - it shows the chain: Object -> Field -> Parent -> GC Root
2. Look at "codebaseUsages" - it shows EXACTLY where this class is used in the codebase
3. Look at "usageContext" - it shows the State class code with the List<T> field
4. Find where items are ADDED to the list but NEVER REMOVED
5. The fix should limit the list size or clear it in dispose()

=== OUTPUT FORMAT ===
Respond with valid JSON only:
{
  "summary": "Brief overview of memory issues found",
  "issues": [
    {
      "title": "Memory: [ClassName] - [X] instances ([Y] KB)",
      "description": "Retained by `[fieldName]` in `[ParentClass]`. The list grows unbounded as items are added but never removed.",
      "severity": "critical|high|medium|low|info",
      "category": "memory",
      "affectedArea": "[sourceLocation]",
      "sourceFile": "main.dart",
      "lineNumber": 96,
      "retentionPath": ["ClassName", "_fieldName", "ParentState", "Widget Tree"],
      "suggestedFixes": ["Specific fix that modifies the ACTUAL code from usageContext"],
      "codeExample": "// BEFORE (from actual usageContext):\\n[quote actual code]\\n\\n// AFTER (with fix):\\n[show modified code]"
    }
  ],
  "recommendations": ["Overall memory optimization recommendations"],
  "metrics": {"tokensUsed": 0, "inputTokens": 0, "outputTokens": 0}
}

=== FIELD REQUIREMENTS ===
- "sourceFile": Extract filename from sourceLocation (e.g., "lib/main.dart" -> "main.dart")
- "lineNumber": Extract line number from sourceLocation (e.g., "lib/main.dart:96" -> 96)
- "retentionPath": Convert retentionPath array to human-readable chain. Clean up field names:
  - Remove @ and hex suffixes: "_eventLog@12345" -> "_eventLog"
  - Keep it readable: ["EventLogEntry", "_eventLog", "_PerformanceTestPageState", "Widget Tree"]
- "description": Use backticks for inline code (e.g., `_eventLog`, `List<EventLogEntry>`) for better readability

=== SEVERITY RULES ===
- critical: >1000 instances OR >1MB total OR clear memory leak pattern
- high: >500 instances OR >500KB total OR unbounded list growth
- medium: >100 instances OR >100KB total
- low: >50 instances
- info: informational, no action needed

=== MEMORY ISSUE PATTERNS TO LOOK FOR ===

1. UNBOUNDED LIST GROWTH (most common):
   - List<T> field in State class
   - Items added in methods but never removed
   - No dispose() cleanup
   Fix: Add size limit or clear in dispose()

2. MISSING DISPOSE:
   - StreamSubscription, AnimationController, TextEditingController
   - Created in initState() but not disposed
   Fix: Add dispose() method to cancel/dispose

3. STATIC REFERENCES:
   - Static fields holding large objects
   - Singletons with cached data
   Fix: Clear caches, use weak references

4. CLOSURE CAPTURES:
   - Anonymous functions capturing State references
   - Timer callbacks holding references
   Fix: Use named methods, cancel timers in dispose()

=== EXAMPLE ANALYSIS ===
If you see:
- className: "EventLogEntry"
- instances: 1200
- retentionPath: ["_eventLog", "_PerformanceTestPageState", "Widget Tree"]
- usageContext shows: "final List<EventLogEntry> _eventLog = [];" and "_eventLog.add(entry);"
- codebaseUsages: [{"file": "lib/main.dart", "line": 338, "code": "_eventLog.add(EventLogEntry(...))"}]

Then the fix is:
```dart
// BEFORE (from codebaseUsages at lib/main.dart:338):
_eventLog.add(entry);

// AFTER (with size limit):
if (_eventLog.length >= 500) {
  _eventLog.removeAt(0);
}
_eventLog.add(entry);
```

ABSOLUTE RULES - VIOLATIONS ARE UNACCEPTABLE:
1. EVERY issue title MUST include the actual sourceLocation
2. ALWAYS quote actual code from codebaseUsages/usageContext in description
3. codeExample MUST show BEFORE (actual code) and AFTER (with fix)
4. Reference actual variable names from the retention path
5. NEVER suggest creating new wrapper classes - modify existing code
6. NEVER invent or substitute class names - use ONLY "className" values from the data
   - WRONG: "Create a CacheManager class..." (invented name)
   - RIGHT: "Modify EventLogEntry usage at lib/main.dart:338..." (actual class from data)
7. If codebaseUsages is available, ALWAYS reference the exact file:line where the class is used
''';

/// The system prompt for chat conversations.
const String chatSystemPrompt = '''
You are an expert Dart and Flutter performance analyst assistant. You help developers understand and fix performance issues in their Flutter applications.

You have access to performance data from the running application. When discussing issues:
- Be specific about what the data shows
- Explain the root cause in simple terms
- Provide actionable fixes with code examples when helpful
- Suggest best practices for Flutter performance

Be conversational and helpful. Use markdown formatting for code blocks.
''';

/// System prompt for class-specific analysis with retention paths.
const String classAnalysisPrompt = '''
You are an expert Flutter/Dart memory analyst. Analyze this specific class and its memory usage.

Given the class information (including source location and retention path), provide:
1. A brief explanation of WHY this class is consuming memory
2. The likely root cause based on the retention path
3. A specific, actionable fix with code example if applicable

Be concise (2-4 sentences for explanation). Focus on the EXACT code change needed.

Example good response:
"This class is retained because _eventLog list grows unbounded in _PerformanceTestPageState. Each call to _runMemoryAllocation() adds items but never removes them.

Fix: Add a size limit to the list:
```dart
if (_eventLog.length >= 500) {
  _eventLog.removeAt(0);
}
_eventLog.add(entry);
```"
''';

/// Abstract interface for LLM providers.
abstract class LlmProvider {
  /// The provider type.
  LlmProviderType get type;

  /// The model being used.
  String get model;

  /// Analyze performance data and return insights.
  Future<AnalysisResult> analyzePerformance(Map<String, dynamic> data);

  /// Stream analysis results for real-time updates.
  Stream<String> analyzePerformanceStream(Map<String, dynamic> data);

  /// Chat with the AI about performance issues.
  Future<String> chat(String message, {List<ChatMessage>? history, Map<String, dynamic>? performanceContext});

  /// Analyze a specific class with retention path context.
  Future<String> analyzeClass(Map<String, dynamic> classContext);

  /// Dispose of resources (HTTP clients, etc.).
  /// Call this when the provider is no longer needed.
  void dispose();

  /// Factory to create the appropriate provider.
  factory LlmProvider.create(LlmConfig config) {
    switch (config.type) {
      case LlmProviderType.claude:
        return ClaudeProvider(config);
      case LlmProviderType.openai:
        return OpenAIProvider(config);
      case LlmProviderType.gemini:
        return GeminiProvider(config);
    }
  }
}

/// Claude (Anthropic) provider implementation.
class ClaudeProvider implements LlmProvider {
  final LlmConfig _config;
  final http.Client _httpClient;
  late final String _model;
  bool _isDisposed = false;

  ClaudeProvider(this._config) : _httpClient = http.Client() {
    _model = _config.effectiveModel;
  }

  @override
  void dispose() {
    if (!_isDisposed) {
      _httpClient.close();
      _isDisposed = true;
    }
  }

  @override
  LlmProviderType get type => LlmProviderType.claude;

  @override
  String get model => _model;

  @override
  Future<AnalysisResult> analyzePerformance(Map<String, dynamic> data) async {
    final startTime = DateTime.now();

    try {
      final response = await _callApi(
        systemPrompt: performanceAnalysisPrompt,
        userMessage: 'Analyze this performance data:\n${jsonEncode(data)}',
      );
      final duration = DateTime.now().difference(startTime);

      final parsed = _parseResponse(response);
      parsed['metrics'] = {
        ...?parsed['metrics'] as Map<String, dynamic>?,
        'responseTimeMs': duration.inMilliseconds,
      };

      return AnalysisResult.fromLlmResponse(
        provider: 'Claude',
        model: _model,
        response: parsed,
      );
    } catch (e) {
      return _createErrorResult(startTime, e);
    }
  }

  @override
  Stream<String> analyzePerformanceStream(Map<String, dynamic> data) async* {
    yield 'Analyzing performance data with Claude...';
    try {
      final result = await analyzePerformance(data);
      yield jsonEncode({
        'summary': result.summary,
        'issueCount': result.issues.length,
        'recommendations': result.recommendations,
      });
    } catch (e) {
      yield 'Error: ${e.toString()}';
    }
  }

  @override
  Future<String> chat(String message, {List<ChatMessage>? history, Map<String, dynamic>? performanceContext}) async {
    try {
      final messages = <Map<String, dynamic>>[];
      if (history != null) {
        for (final msg in history) {
          messages.add(msg.toJson());
        }
      }
      String userContent = message;
      if (performanceContext != null) {
        userContent = 'Current performance data context:\n${jsonEncode(performanceContext)}\n\nUser question: $message';
      }
      messages.add({'role': 'user', 'content': userContent});

      return await _callApiWithMessages(systemPrompt: chatSystemPrompt, messages: messages);
    } catch (e) {
      return _formatError(e);
    }
  }

  @override
  Future<String> analyzeClass(Map<String, dynamic> classContext) async {
    try {
      return await _callApi(
        systemPrompt: classAnalysisPrompt,
        userMessage: 'Analyze this class and provide specific fixes:\n${jsonEncode(classContext)}',
      );
    } catch (e) {
      return _formatError(e);
    }
  }

  Future<String> _callApi({required String systemPrompt, required String userMessage}) async {
    return _callApiWithMessages(
      systemPrompt: systemPrompt,
      messages: [{'role': 'user', 'content': userMessage}],
    );
  }

  Future<String> _callApiWithMessages({required String systemPrompt, required List<Map<String, dynamic>> messages}) async {
    final uri = _config.proxyUrl('https://api.anthropic.com/v1/messages');
    final body = jsonEncode({
      'model': _model,
      'max_tokens': _config.maxTokens ?? 4096,
      'temperature': _config.temperature ?? 0.3,
      'system': systemPrompt,
      'messages': messages,
    });

    final response = await _httpClient.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': _config.apiKey,
        'anthropic-version': '2023-06-01',
        'anthropic-dangerous-direct-browser-access': 'true',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception('Claude API error: ${response.statusCode} - ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final content = json['content'] as List<dynamic>;
    if (content.isNotEmpty) {
      return content.first['text'] as String;
    }
    throw Exception('Empty response from Claude API');
  }

  AnalysisResult _createErrorResult(DateTime startTime, Object e) {
    return AnalysisResult(
      timestamp: DateTime.now(),
      provider: 'Claude',
      model: _model,
      issues: [],
      summary: 'Analysis failed: ${_formatError(e)}',
      recommendations: [],
      metrics: AnalysisMetrics(
        tokensUsed: 0,
        inputTokens: 0,
        outputTokens: 0,
        responseTime: DateTime.now().difference(startTime),
        errorMessage: e.toString(),
      ),
    );
  }

  String _formatError(Object e) {
    final error = e.toString();
    if (error.contains('Failed to fetch') || error.contains('ClientException')) {
      return 'CORS Error: Browser security prevents direct API calls. '
          'Configure a CORS proxy in Settings, or use Google Gemini which has better browser support.';
    }
    return error;
  }

  Map<String, dynamic> _parseResponse(String response) {
    try {
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (jsonMatch != null) {
        return jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      }
      return jsonDecode(response) as Map<String, dynamic>;
    } catch (e) {
      return {'summary': response, 'issues': <Map<String, dynamic>>[], 'recommendations': <String>[]};
    }
  }
}

/// OpenAI provider implementation.
class OpenAIProvider implements LlmProvider {
  final LlmConfig _config;
  final http.Client _httpClient;
  late final String _model;
  bool _isDisposed = false;

  OpenAIProvider(this._config) : _httpClient = http.Client() {
    _model = _config.effectiveModel;
  }

  @override
  void dispose() {
    if (!_isDisposed) {
      _httpClient.close();
      _isDisposed = true;
    }
  }

  @override
  LlmProviderType get type => LlmProviderType.openai;

  @override
  String get model => _model;

  @override
  Future<AnalysisResult> analyzePerformance(Map<String, dynamic> data) async {
    final startTime = DateTime.now();
    try {
      final response = await _callApi(
        systemPrompt: performanceAnalysisPrompt,
        userMessage: 'Analyze this performance data:\n${jsonEncode(data)}',
        jsonMode: true,
      );
      final duration = DateTime.now().difference(startTime);
      final parsed = _parseResponse(response);
      parsed['metrics'] = {...?parsed['metrics'] as Map<String, dynamic>?, 'responseTimeMs': duration.inMilliseconds};
      return AnalysisResult.fromLlmResponse(provider: 'OpenAI', model: _model, response: parsed);
    } catch (e) {
      return _createErrorResult(startTime, e);
    }
  }

  @override
  Stream<String> analyzePerformanceStream(Map<String, dynamic> data) async* {
    yield 'Analyzing performance data with OpenAI...';
    try {
      final result = await analyzePerformance(data);
      yield jsonEncode({'summary': result.summary, 'issueCount': result.issues.length, 'recommendations': result.recommendations});
    } catch (e) {
      yield 'Error: ${e.toString()}';
    }
  }

  @override
  Future<String> chat(String message, {List<ChatMessage>? history, Map<String, dynamic>? performanceContext}) async {
    try {
      final messages = <Map<String, dynamic>>[{'role': 'system', 'content': chatSystemPrompt}];
      if (history != null) {
        for (final msg in history) {
          messages.add(msg.toJson());
        }
      }
      String userContent = message;
      if (performanceContext != null) {
        userContent = 'Current performance data context:\n${jsonEncode(performanceContext)}\n\nUser question: $message';
      }
      messages.add({'role': 'user', 'content': userContent});
      return await _callApiWithMessages(messages: messages);
    } catch (e) {
      return _formatError(e);
    }
  }

  @override
  Future<String> analyzeClass(Map<String, dynamic> classContext) async {
    try {
      return await _callApi(
        systemPrompt: classAnalysisPrompt,
        userMessage: 'Analyze this class and provide specific fixes:\n${jsonEncode(classContext)}',
      );
    } catch (e) {
      return _formatError(e);
    }
  }

  Future<String> _callApi({required String systemPrompt, required String userMessage, bool jsonMode = false}) async {
    return _callApiWithMessages(
      messages: [{'role': 'system', 'content': systemPrompt}, {'role': 'user', 'content': userMessage}],
      jsonMode: jsonMode,
    );
  }

  Future<String> _callApiWithMessages({required List<Map<String, dynamic>> messages, bool jsonMode = false}) async {
    final uri = _config.proxyUrl('https://api.openai.com/v1/chat/completions');
    final bodyMap = <String, dynamic>{
      'model': _model,
      'max_tokens': _config.maxTokens ?? 4096,
      'temperature': _config.temperature ?? 0.3,
      'messages': messages,
    };
    if (jsonMode) bodyMap['response_format'] = {'type': 'json_object'};

    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${_config.apiKey}'},
      body: jsonEncode(bodyMap),
    );

    if (response.statusCode != 200) {
      throw Exception('OpenAI API error: ${response.statusCode} - ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>;
    if (choices.isNotEmpty) {
      return (choices.first['message'] as Map<String, dynamic>)['content'] as String;
    }
    throw Exception('Empty response from OpenAI API');
  }

  AnalysisResult _createErrorResult(DateTime startTime, Object e) {
    return AnalysisResult(
      timestamp: DateTime.now(), provider: 'OpenAI', model: _model, issues: [],
      summary: 'Analysis failed: ${_formatError(e)}', recommendations: [],
      metrics: AnalysisMetrics(tokensUsed: 0, inputTokens: 0, outputTokens: 0,
        responseTime: DateTime.now().difference(startTime), errorMessage: e.toString()),
    );
  }

  String _formatError(Object e) {
    final error = e.toString();
    if (error.contains('Failed to fetch') || error.contains('ClientException')) {
      return 'CORS Error: Browser security prevents direct API calls. '
          'Configure a CORS proxy in Settings, or use Google Gemini which has better browser support.';
    }
    return error;
  }

  Map<String, dynamic> _parseResponse(String response) {
    try {
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (jsonMatch != null) return jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      return jsonDecode(response) as Map<String, dynamic>;
    } catch (e) {
      return {'summary': response, 'issues': <Map<String, dynamic>>[], 'recommendations': <String>[]};
    }
  }
}

/// Google Gemini provider implementation.
/// Gemini has better CORS support for browser-based applications.
class GeminiProvider implements LlmProvider {
  final LlmConfig _config;
  final http.Client _httpClient;
  late final String _model;
  bool _isDisposed = false;

  GeminiProvider(this._config) : _httpClient = http.Client() {
    _model = _config.effectiveModel;
  }

  @override
  void dispose() {
    if (!_isDisposed) {
      _httpClient.close();
      _isDisposed = true;
    }
  }

  @override
  LlmProviderType get type => LlmProviderType.gemini;

  @override
  String get model => _model;

  @override
  Future<AnalysisResult> analyzePerformance(Map<String, dynamic> data) async {
    final startTime = DateTime.now();
    try {
      final prompt = '$performanceAnalysisPrompt\n\nAnalyze this performance data:\n${jsonEncode(data)}';
      final response = await _callApi(prompt);
      final duration = DateTime.now().difference(startTime);
      final parsed = _parseResponse(response);
      parsed['metrics'] = {...?parsed['metrics'] as Map<String, dynamic>?, 'responseTimeMs': duration.inMilliseconds};
      return AnalysisResult.fromLlmResponse(provider: 'Gemini', model: _model, response: parsed);
    } catch (e) {
      return _createErrorResult(startTime, e);
    }
  }

  @override
  Stream<String> analyzePerformanceStream(Map<String, dynamic> data) async* {
    yield 'Analyzing performance data with Gemini...';
    try {
      final result = await analyzePerformance(data);
      yield jsonEncode({'summary': result.summary, 'issueCount': result.issues.length, 'recommendations': result.recommendations});
    } catch (e) {
      yield 'Error: ${e.toString()}';
    }
  }

  @override
  Future<String> chat(String message, {List<ChatMessage>? history, Map<String, dynamic>? performanceContext}) async {
    try {
      final contents = <Map<String, dynamic>>[];

      // Add system context as first user message
      contents.add({
        'role': 'user',
        'parts': [{'text': chatSystemPrompt}]
      });
      contents.add({
        'role': 'model',
        'parts': [{'text': 'I understand. I am a Flutter performance analyst assistant ready to help.'}]
      });

      // Add history
      if (history != null) {
        for (final msg in history) {
          contents.add({
            'role': msg.role == 'user' ? 'user' : 'model',
            'parts': [{'text': msg.content}]
          });
        }
      }

      // Add current message with context
      String userContent = message;
      if (performanceContext != null) {
        userContent = 'Current performance data context:\n${jsonEncode(performanceContext)}\n\nUser question: $message';
      }
      contents.add({'role': 'user', 'parts': [{'text': userContent}]});

      return await _callApiWithContents(contents);
    } catch (e) {
      return _formatError(e);
    }
  }

  @override
  Future<String> analyzeClass(Map<String, dynamic> classContext) async {
    try {
      final prompt = '$classAnalysisPrompt\n\nAnalyze this class and provide specific fixes:\n${jsonEncode(classContext)}';
      return await _callApi(prompt);
    } catch (e) {
      return _formatError(e);
    }
  }

  Future<String> _callApi(String prompt) async {
    return _callApiWithContents([
      {'role': 'user', 'parts': [{'text': prompt}]}
    ]);
  }

  Future<String> _callApiWithContents(List<Map<String, dynamic>> contents) async {
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=${_config.apiKey}');

    final body = jsonEncode({
      'contents': contents,
      'generationConfig': {
        'temperature': _config.temperature ?? 0.3,
        'maxOutputTokens': _config.maxTokens ?? 4096,
      },
    });

    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception('Gemini API error: ${response.statusCode} - ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = json['candidates'] as List<dynamic>?;
    if (candidates != null && candidates.isNotEmpty) {
      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>?;
      if (parts != null && parts.isNotEmpty) {
        return parts.first['text'] as String;
      }
    }
    throw Exception('Empty response from Gemini API');
  }

  AnalysisResult _createErrorResult(DateTime startTime, Object e) {
    return AnalysisResult(
      timestamp: DateTime.now(), provider: 'Gemini', model: _model, issues: [],
      summary: 'Analysis failed: ${_formatError(e)}', recommendations: [],
      metrics: AnalysisMetrics(tokensUsed: 0, inputTokens: 0, outputTokens: 0,
        responseTime: DateTime.now().difference(startTime), errorMessage: e.toString()),
    );
  }

  String _formatError(Object e) {
    final error = e.toString();
    if (error.contains('Failed to fetch') || error.contains('ClientException')) {
      return 'Network Error: Unable to reach Gemini API. Check your internet connection and API key.';
    }
    return error;
  }

  Map<String, dynamic> _parseResponse(String response) {
    try {
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (jsonMatch != null) return jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      return jsonDecode(response) as Map<String, dynamic>;
    } catch (e) {
      return {'summary': response, 'issues': <Map<String, dynamic>>[], 'recommendations': <String>[]};
    }
  }
}
