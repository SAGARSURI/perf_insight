/// Performance AI Extension - DevTools Extension Entry Point
///
/// A DevTools extension that provides LLM-powered performance insights
/// for Dart & Flutter applications.

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/models/performance_data.dart';
import 'src/screens/chat_screen.dart';
import 'src/screens/home_screen.dart';
import 'src/screens/settings_screen.dart';

void main() {
  runApp(const PerformanceAIExtension());
}

/// Root widget for the Performance AI DevTools extension.
class PerformanceAIExtension extends StatelessWidget {
  const PerformanceAIExtension({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('=== PerformanceAIExtension.build called ===');
    return DevToolsExtension(
      child: Builder(
        builder: (context) {
          debugPrint('=== DevToolsExtension child builder called ===');
          return const PerformanceAIApp();
        },
      ),
    );
  }
}

/// Main application shell with navigation.
class PerformanceAIApp extends StatefulWidget {
  const PerformanceAIApp({super.key});

  @override
  State<PerformanceAIApp> createState() => _PerformanceAIAppState();
}

class _PerformanceAIAppState extends State<PerformanceAIApp> {
  int _selectedIndex = 0;
  PerformanceSnapshot? _lastSnapshot;

  void _updateSnapshot(PerformanceSnapshot? snapshot) {
    setState(() {
      _lastSnapshot = snapshot;
    });
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('=== PerformanceAIApp.build called ===');
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          // Navigation rail
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.analytics_outlined),
                selectedIcon: Icon(Icons.analytics),
                label: Text('Analysis'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.chat_outlined),
                selectedIcon: Icon(Icons.chat),
                label: Text('Chat'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // Content area
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0:
        return HomeScreen(
          onSnapshotCollected: _updateSnapshot,
        );
      case 1:
        return ChatScreen(
          performanceContext: _lastSnapshot,
        );
      case 2:
        return SettingsScreen(
          onSettingsSaved: () {
            // Navigate back to analysis after saving
            setState(() => _selectedIndex = 0);
          },
        );
      default:
        return const HomeScreen();
    }
  }
}
