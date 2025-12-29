/// Settings screen for API key management and privacy controls.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../llm/llm_provider.dart';
import '../privacy/data_redactor.dart';

/// Settings screen for configuring the extension.
class SettingsScreen extends StatefulWidget {
  final VoidCallback? onSettingsSaved;

  const SettingsScreen({super.key, this.onSettingsSaved});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _claudeKeyController = TextEditingController();
  final _openaiKeyController = TextEditingController();
  final _geminiKeyController = TextEditingController();
  final _corsProxyController = TextEditingController();

  LlmProviderType _selectedProvider = LlmProviderType.claude;
  PrivacyLevel _privacyLevel = PrivacyLevel.maximum;
  bool _isLoading = true;
  bool _obscureClaudeKey = true;
  bool _obscureOpenAIKey = true;
  bool _obscureGeminiKey = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _claudeKeyController.dispose();
    _openaiKeyController.dispose();
    _geminiKeyController.dispose();
    _corsProxyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _claudeKeyController.text = prefs.getString('claude_api_key') ?? '';
      _openaiKeyController.text = prefs.getString('openai_api_key') ?? '';
      _geminiKeyController.text = prefs.getString('gemini_api_key') ?? '';
      _corsProxyController.text = prefs.getString('cors_proxy_url') ?? '';

      final providerStr = prefs.getString('selected_provider') ?? 'claude';
      _selectedProvider = LlmProviderType.values.firstWhere(
        (p) => p.name == providerStr,
        orElse: () => LlmProviderType.claude,
      );

      final privacyStr = prefs.getString('privacy_level') ?? 'maximum';
      _privacyLevel = PrivacyLevel.values.firstWhere(
        (l) => l.name == privacyStr,
        orElse: () => PrivacyLevel.maximum,
      );

      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('claude_api_key', _claudeKeyController.text.trim());
    await prefs.setString('openai_api_key', _openaiKeyController.text.trim());
    await prefs.setString('gemini_api_key', _geminiKeyController.text.trim());
    await prefs.setString('cors_proxy_url', _corsProxyController.text.trim());
    await prefs.setString('selected_provider', _selectedProvider.name);
    await prefs.setString('privacy_level', _privacyLevel.name);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
      widget.onSettingsSaved?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('LLM Provider'),
          const SizedBox(height: 8),
          _buildProviderSelector(),
          const SizedBox(height: 24),
          _buildSectionHeader('API Keys'),
          const SizedBox(height: 8),
          _buildApiKeyField(
            label: 'Claude (Anthropic) API Key',
            controller: _claudeKeyController,
            obscure: _obscureClaudeKey,
            onToggleObscure: () =>
                setState(() => _obscureClaudeKey = !_obscureClaudeKey),
            hint: 'sk-ant-...',
          ),
          const SizedBox(height: 16),
          _buildApiKeyField(
            label: 'OpenAI API Key',
            controller: _openaiKeyController,
            obscure: _obscureOpenAIKey,
            onToggleObscure: () =>
                setState(() => _obscureOpenAIKey = !_obscureOpenAIKey),
            hint: 'sk-...',
          ),
          const SizedBox(height: 16),
          _buildApiKeyField(
            label: 'Google Gemini API Key',
            controller: _geminiKeyController,
            obscure: _obscureGeminiKey,
            onToggleObscure: () =>
                setState(() => _obscureGeminiKey = !_obscureGeminiKey),
            hint: 'AIza...',
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('CORS Proxy (Optional)'),
          const SizedBox(height: 8),
          _buildCorsProxyField(),
          const SizedBox(height: 8),
          _buildCorsProxyHelp(),
          const SizedBox(height: 24),
          _buildSectionHeader('Privacy Settings'),
          const SizedBox(height: 8),
          _buildPrivacySelector(),
          const SizedBox(height: 8),
          _buildPrivacyDescription(),
          const SizedBox(height: 16),
          _buildCorsNote(),
          const SizedBox(height: 32),
          _buildSaveButton(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }

  Widget _buildProviderSelector() {
    return SegmentedButton<LlmProviderType>(
      segments: const [
        ButtonSegment(
          value: LlmProviderType.claude,
          label: Text('Claude'),
          icon: Icon(Icons.smart_toy),
        ),
        ButtonSegment(
          value: LlmProviderType.openai,
          label: Text('OpenAI'),
          icon: Icon(Icons.psychology),
        ),
        ButtonSegment(
          value: LlmProviderType.gemini,
          label: Text('Gemini'),
          icon: Icon(Icons.auto_awesome),
        ),
      ],
      selected: {_selectedProvider},
      onSelectionChanged: (selection) {
        setState(() => _selectedProvider = selection.first);
      },
    );
  }

  Widget _buildApiKeyField({
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggleObscure,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
          onPressed: onToggleObscure,
        ),
      ),
    );
  }

  Widget _buildCorsProxyField() {
    return TextField(
      controller: _corsProxyController,
      decoration: const InputDecoration(
        labelText: 'CORS Proxy URL',
        hintText: 'http://localhost:8010/proxy',
        border: OutlineInputBorder(),
        helperText: 'Required for Claude/OpenAI in browser',
      ),
    );
  }

  Widget _buildCorsProxyHelp() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Quick Setup for Claude',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '1. Run in terminal:\n'
            'npx local-cors-proxy --proxyUrl https://api.anthropic.com --port 8010\n\n'
            '2. Enter here: http://localhost:8010/proxy',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacySelector() {
    return DropdownButtonFormField<PrivacyLevel>(
      value: _privacyLevel,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        labelText: 'Privacy Level',
      ),
      items: PrivacyLevel.values.map((level) {
        return DropdownMenuItem(
          value: level,
          child: Text(_getPrivacyLevelLabel(level)),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() => _privacyLevel = value);
        }
      },
    );
  }

  String _getPrivacyLevelLabel(PrivacyLevel level) {
    switch (level) {
      case PrivacyLevel.maximum:
        return 'Maximum (Recommended)';
      case PrivacyLevel.partial:
        return 'Partial (Keep function names)';
      case PrivacyLevel.minimal:
        return 'Minimal (Keep most identifiers)';
    }
  }

  Widget _buildPrivacyDescription() {
    String description;
    switch (_privacyLevel) {
      case PrivacyLevel.maximum:
        description =
            'Only aggregated metrics are sent. Function names, class names, and file paths are anonymized.';
        break;
      case PrivacyLevel.partial:
        description =
            'Function and class names are preserved. File paths and user data are redacted.';
        break;
      case PrivacyLevel.minimal:
        description =
            'Most identifiers are preserved. Only obvious PII patterns are redacted.';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorsNote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_outlined,
            color: Theme.of(context).colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Browser CORS Note',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onTertiaryContainer,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'If you encounter "Failed to fetch" errors, this is due to browser CORS restrictions. Consider using Google Gemini which has better browser support.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onTertiaryContainer,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _saveSettings,
        icon: const Icon(Icons.save),
        label: const Text('Save Settings'),
      ),
    );
  }
}

/// Helper to load saved settings.
class SettingsLoader {
  static Future<LlmConfig?> loadActiveConfig() async {
    final prefs = await SharedPreferences.getInstance();

    final providerStr = prefs.getString('selected_provider') ?? 'claude';
    final provider = LlmProviderType.values.firstWhere(
      (p) => p.name == providerStr,
      orElse: () => LlmProviderType.claude,
    );

    String? apiKey;
    switch (provider) {
      case LlmProviderType.claude:
        apiKey = prefs.getString('claude_api_key');
        break;
      case LlmProviderType.openai:
        apiKey = prefs.getString('openai_api_key');
        break;
      case LlmProviderType.gemini:
        apiKey = prefs.getString('gemini_api_key');
        break;
    }

    if (apiKey == null || apiKey.isEmpty) {
      return null;
    }

    final corsProxyUrl = prefs.getString('cors_proxy_url');

    return LlmConfig(
      type: provider,
      apiKey: apiKey,
      corsProxyUrl: corsProxyUrl?.isNotEmpty == true ? corsProxyUrl : null,
    );
  }

  static Future<PrivacyLevel> loadPrivacyLevel() async {
    final prefs = await SharedPreferences.getInstance();
    final privacyStr = prefs.getString('privacy_level') ?? 'maximum';

    return PrivacyLevel.values.firstWhere(
      (l) => l.name == privacyStr,
      orElse: () => PrivacyLevel.maximum,
    );
  }
}
