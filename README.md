# Perf Insight

**AI-Powered Memory Analysis for Flutter DevTools**

A Flutter DevTools extension that brings AI-powered insights directly into your debugging workflow. Stop guessing about memory issues — get actionable recommendations powered by LLMs.

## Features

- **Memory Treemap Visualization** — See your app's memory usage at a glance with an interactive treemap
- **Retention Path Analysis** — Understand *why* objects are retained in memory
- **Source Location Tracking** — Jump directly to the code responsible for allocations
- **AI-Powered Insights** — Get intelligent suggestions for memory optimization
- **Real-time Monitoring** — Track memory usage as your app runs

## Screenshots

*Coming soon*

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/SAGARSURI/perf_insight.git
```

### 2. Build the extension

```bash
cd perf_insight
flutter pub get
flutter build web
```

### 3. Add to your Flutter app

Add the extension reference to your app's `pubspec.yaml`:

```yaml
dev_dependencies:
  perf_insight:
    path: /path/to/perf_insight
```

Or copy the built extension to your app's `extension/devtools/` directory.

### 4. Configure AI Provider (Optional)

To enable AI-powered insights, configure your LLM provider in the extension settings. Supports:
- OpenAI
- Anthropic Claude
- Google Gemini
- Local models via Ollama

## Usage

1. Run your Flutter app in **debug mode** (required for source locations and code snippets)
2. Open Flutter DevTools
3. Navigate to the "Perf Insight" tab
4. Click "Capture Snapshot" to analyze memory

### Debug vs Profile Mode

| Feature | Debug Mode | Profile Mode |
|---------|------------|--------------|
| Memory Treemap | ✅ | ✅ |
| Instance Counts | ✅ | ✅ |
| Retention Paths | ✅ | ✅ |
| Source Locations | ✅ | File only (no line numbers) |
| Code Snippets | ✅ | ❌ |
| AI Insights | ✅ | ✅ |

## How It Works

Perf Insight uses the Dart VM Service Protocol to:

1. **Collect Allocation Data** — Captures heap snapshots and allocation profiles
2. **Analyze Retention Paths** — Traces object references back to GC roots
3. **Resolve Source Locations** — Maps allocations to your source code
4. **Generate AI Insights** — Sends anonymized context to your configured LLM for analysis

## Configuration

The extension is configured via `extension/devtools/config.yaml`:

```yaml
name: perf_insight
version: 1.0.8
materialIconCodePoint: '0xe1b1'
requiresConnection: true
```

## Requirements

- Flutter 3.0+
- Dart 3.0+
- A running Flutter application (connected to DevTools)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Author

**Sagar Suri** — [@sagaborwing](https://twitter.com/sagaborwing)

---

*Built with Flutter DevTools Extensions API*
