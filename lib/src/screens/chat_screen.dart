/// Chat screen for interactive AI conversations about performance.

import 'package:flutter/material.dart';

import '../llm/llm_provider.dart';
import '../models/performance_data.dart';
import 'settings_screen.dart';

/// Chat screen for asking AI about performance issues.
class ChatScreen extends StatefulWidget {
  final PerformanceSnapshot? performanceContext;

  const ChatScreen({super.key, this.performanceContext});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  LlmProvider? _provider;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeProvider();
    _addWelcomeMessage();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeProvider() async {
    final config = await SettingsLoader.loadActiveConfig();
    if (config != null) {
      setState(() {
        _provider = LlmProvider.create(config);
      });
    }
  }

  void _addWelcomeMessage() {
    _messages.add(ChatMessage(
      role: 'assistant',
      content: '''Hello! I'm your Performance AI Assistant. I can help you:

- Understand performance issues in your Flutter app
- Explain CPU hotspots and memory leaks
- Suggest optimizations and best practices
- Answer questions about Dart/Flutter performance

${widget.performanceContext != null ? 'I have access to your current performance data. Ask me anything about it!' : 'Run an analysis first to give me context about your app\'s performance, or ask general questions.'}

How can I help you today?''',
    ));
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    if (_provider == null) {
      setState(() {
        _errorMessage = 'Please configure your API key in settings first.';
      });
      return;
    }

    // Add user message
    setState(() {
      _messages.add(ChatMessage(role: 'user', content: message));
      _messageController.clear();
      _isLoading = true;
      _errorMessage = null;
    });

    _scrollToBottom();

    try {
      // Get conversation history (excluding welcome message for API)
      final history = _messages
          .where((m) => m != _messages.first)
          .take(_messages.length - 2) // Exclude the new user message
          .toList();

      // Prepare performance context with detailed data
      Map<String, dynamic>? context;
      if (widget.performanceContext != null) {
        final snapshot = widget.performanceContext!;
        context = {};

        // Add detailed memory info if available
        if (snapshot.memory != null) {
          final mem = snapshot.memory!;

          // Separate user classes from internal classes
          final userClasses = mem.topAllocations.where((a) => a.isUserClass).toList();
          final internalClasses = mem.topAllocations.where((a) => !a.isUserClass).take(10).toList();

          context['memory'] = {
            'heapUsedMB': mem.heapUsedMB.toStringAsFixed(2),
            'heapCapacityMB': mem.heapCapacityMB.toStringAsFixed(2),
            'percentUsed': mem.percentUsed.toStringAsFixed(1),
            'externalUsageMB': (mem.externalUsage / (1024 * 1024)).toStringAsFixed(2),
            // User/App classes - MOST IMPORTANT for analysis
            'appClasses': userClasses.take(20).map((a) => <String, dynamic>{
              'className': a.className,
              'library': a.libraryUri ?? 'unknown',
              'instanceCount': a.instanceCount,
              'totalBytes': a.totalBytes,
              'totalMB': (a.totalBytes / (1024 * 1024)).toStringAsFixed(3),
            }).toList(),
            // Internal/Framework classes for context
            'frameworkOverhead': internalClasses.map((a) => <String, dynamic>{
              'className': a.className,
              'instanceCount': a.instanceCount,
              'totalMB': (a.totalBytes / (1024 * 1024)).toStringAsFixed(3),
            }).toList(),
          };
        }

        // Add detailed CPU info if available
        if (snapshot.cpu != null) {
          final cpu = snapshot.cpu!;

          // Filter for user code functions (not dart: or flutter framework)
          bool isUserFunction(FunctionSample f) {
            final lib = f.libraryUri ?? '';
            if (lib.startsWith('dart:')) return false;
            if (lib.contains('package:flutter/')) return false;
            if (f.functionName.startsWith('_')) return false;
            return true;
          }

          final userFunctions = cpu.topFunctions.where(isUserFunction).toList();
          final frameworkFunctions = cpu.topFunctions.where((f) => !isUserFunction(f)).take(5).toList();

          context['cpu'] = {
            'sampleCount': cpu.sampleCount,
            'totalCpuTimeMs': cpu.totalCpuTimeMs.toStringAsFixed(2),
            // User/App functions - MOST IMPORTANT for analysis
            'appFunctions': userFunctions.take(15).map((f) => <String, dynamic>{
              'functionName': f.functionName,
              'className': f.className ?? 'N/A',
              'library': f.libraryUri ?? 'N/A',
              'exclusiveTicks': f.exclusiveTicks,
              'inclusiveTicks': f.inclusiveTicks,
              'percentageOfCpu': f.percentage.toStringAsFixed(2),
            }).toList(),
            // Framework overhead for context
            'frameworkOverhead': frameworkFunctions.map((f) => <String, dynamic>{
              'functionName': f.functionName,
              'percentageOfCpu': f.percentage.toStringAsFixed(2),
            }).toList(),
          };
        }

        // Add detailed timeline info if available
        if (snapshot.timeline != null) {
          final timeline = snapshot.timeline!;
          context['timeline'] = {
            'totalFrames': timeline.totalFrames,
            'jankFrameCount': timeline.jankFrameCount,
            'jankPercent': timeline.jankPercent.toStringAsFixed(1),
            'averageFrameTimeMs': timeline.averageFrameTimeMs.toStringAsFixed(2),
            'p95FrameTimeMs': timeline.p95FrameTimeMs.toStringAsFixed(2),
            'p99FrameTimeMs': timeline.p99FrameTimeMs.toStringAsFixed(2),
            // Include worst frames for analysis
            'worstFrames': timeline.frames
                .where((f) => f.isJank)
                .take(5)
                .map((f) => <String, dynamic>{
                  'totalTimeMs': (f.totalTimeUs / 1000).toStringAsFixed(2),
                  'buildTimeMs': (f.buildTimeUs / 1000).toStringAsFixed(2),
                  'rasterTimeMs': (f.rasterTimeUs / 1000).toStringAsFixed(2),
                })
                .toList(),
          };
        }
      }

      // Get AI response
      final response = await _provider!.chat(
        message,
        history: history,
        performanceContext: context,
      );

      setState(() {
        _messages.add(ChatMessage(role: 'assistant', content: response));
        _isLoading = false;
      });

      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to get response: $e';
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      _addWelcomeMessage();
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1),
          Expanded(
            child: _buildMessageList(),
          ),
          if (_errorMessage != null) _buildErrorBanner(),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            Icons.chat,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Performance AI Chat',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  widget.performanceContext != null
                      ? 'Context: Performance data loaded'
                      : 'No performance data - run analysis for context',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear chat',
            onPressed: _clearChat,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isLoading) {
          return _buildLoadingIndicator();
        }
        return _buildMessageBubble(_messages[index]);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.role == 'user';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(
                Icons.smart_toy,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomLeft: isUser ? null : const Radius.circular(4),
                  bottomRight: isUser ? const Radius.circular(4) : null,
                ),
              ),
              child: SelectableText(
                message.content,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isUser
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurface,
                    ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.secondary,
              child: const Icon(
                Icons.person,
                size: 18,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: const Icon(
              Icons.smart_toy,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16).copyWith(
                bottomLeft: const Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Thinking...',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _errorMessage = null),
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Ask about performance issues...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton(
            onPressed: _isLoading ? null : _sendMessage,
            mini: true,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
