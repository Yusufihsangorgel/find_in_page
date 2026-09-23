import 'dart:io';

import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/readme_quickstart.dart' as quickstart;

const _blockStart = '<!-- readme-quickstart:start -->\n```dart\n';
const _blockEnd = '```\n<!-- readme-quickstart:end -->';

String _normalizeLineEndings(String value) =>
    value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

Future<void> _openFind(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

void main() {
  testWidgets('README quickstart runs without a controller or registration', (
    tester,
  ) async {
    final readme = _normalizeLineEndings(File('README.md').readAsStringSync());
    final fixture = _normalizeLineEndings(
      File('test/fixtures/readme_quickstart.dart').readAsStringSync(),
    );
    final starts = _blockStart.allMatches(readme).toList();
    final ends = _blockEnd.allMatches(readme).toList();

    expect(starts, hasLength(1));
    expect(ends, hasLength(1));
    expect(ends.single.start, greaterThan(starts.single.end));
    expect(
      readme.substring(starts.single.end, ends.single.start),
      fixture,
    );

    final originalPlatform = debugDefaultTargetPlatformOverride;
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      quickstart.main();
      await tester.pump();

      expect(find.byType(FindBar), findsNothing);
      await _openFind(tester, LogicalKeyboardKey.controlLeft);
      expect(find.byType(FindBar), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'plain text');
      await tester.pump();
      expect(find.text('1/2'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(FindBar), findsNothing);

      await _openFind(tester, LogicalKeyboardKey.controlLeft);
      final reopenedBar = tester.widget<FindBar>(find.byType(FindBar));
      final reopenedField = tester.widget<TextField>(find.byType(TextField));
      expect(reopenedBar.controller.query, isEmpty);
      expect(reopenedBar.controller.matchCount, 0);
      expect(reopenedField.controller!.text, isEmpty);
      expect(find.text('1/2'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await _openFind(tester, LogicalKeyboardKey.metaLeft);
      expect(find.byType(FindBar), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatform;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}
