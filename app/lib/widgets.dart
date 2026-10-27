// Small widgets and styles shared by the screener and the company page.
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
