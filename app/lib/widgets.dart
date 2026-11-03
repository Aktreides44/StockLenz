// Small widgets and styles shared by the screener and the company page.
import 'dart:async';
import 'dart:io' show Platform, Process;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'format.dart';

/// Tabular figures give every digit the same width, so numbers line up in columns.
const TextStyle numberStyle = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// "—" for a missing value, with the reason as a tooltip. Never shown as 0.
class MissingValue extends StatelessWidget {
  const MissingValue(this.reason, {super.key});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: reason,
      child: Text(missingValue, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
    );
  }
}

/// A number, in red when it is negative.
class NumberText extends StatelessWidget {
  const NumberText(this.text, {super.key, required this.value, this.bold = false});

  final String text;
  final double value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: numberStyle.copyWith(
        color: value < 0 ? Theme.of(context).colorScheme.error : null,
        fontWeight: bold ? FontWeight.bold : null,
      ),
    );
  }
}

/// Open a web page in the default browser.
///
/// On Windows we ask Explorer to open it, which needs no extra plugin. On other platforms
/// (later: iOS) we copy the link to the clipboard for now.
Future<void> openInBrowser(BuildContext context, String url) async {
  if (Platform.isWindows) {
    await Process.run('explorer.exe', [url]);
    return;
  }
  await Clipboard.setData(ClipboardData(text: url));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Link copied: $url')));
  }
}


/// A spinner while data loads. If it takes longer than a few seconds, the server on
/// Render's free tier is probably asleep, so we say that it is waking up.
class LoadingMessage extends StatefulWidget {
  const LoadingMessage({super.key});

  /// After this long without an answer we show the "waking up" text.
  static const wakingUpAfter = Duration(seconds: 5);

  @override
  State<LoadingMessage> createState() => _LoadingMessageState();
}

class _LoadingMessageState extends State<LoadingMessage> {
  late final Timer _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(LoadingMessage.wakingUpAfter, () => setState(() => _slow = true));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (_slow) ...[
            const SizedBox(height: 16),
            const Text('Waking up the server…'),
            const SizedBox(height: 4),
            Text(
              'The free server sleeps when nobody uses it. This can take up to a minute.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// "Can't connect" with the reason and a Retry button.
class ConnectionError extends StatelessWidget {
  const ConnectionError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: colors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text("Can't connect", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: colors.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
