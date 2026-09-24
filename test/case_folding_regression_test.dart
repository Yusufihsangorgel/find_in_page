import 'package:find_in_page/find_in_page.dart';
import 'package:find_in_page/src/text_fold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _TextSource implements FindableSource {
  _TextSource(this.findableText);

  @override
  final String findableText;

  @override
  BuildContext? get findableContext => null;
}

void main() {
  testWidgets('U+0130 searches return original UTF-16 ranges', (tester) async {
    const rows = <(String, String, int, int, String, bool)>[
      ('İstanbul ve İzmir', 'izmir', 12, 17, 'İzmir', false),
      ('DİYARBAKIR', 'diyarbakir', 0, 10, 'DİYARBAKIR', false),
      ('aİb', 'b', 2, 3, 'b', false),
      ('İİİ x', 'x', 4, 5, 'x', false),
      ('İstanbul', 'istanbul', 0, 8, 'İstanbul', true),
    ];

    for (final (text, query, start, end, slice, diacriticSensitive) in rows) {
      final controller = FindInPageController()..register(_TextSource(text));
      controller.search(
        query,
        diacriticSensitive: diacriticSensitive,
      );
      await tester.pump();

      expect(controller.matchCount, 1, reason: '$text / $query');
      final match = controller.activeMatch!;
      expect(match.start, start, reason: '$text / $query');
      expect(match.end, end, reason: '$text / $query');
      expect(match.start, inInclusiveRange(0, text.length));
      expect(match.end, inInclusiveRange(match.start, text.length));
      expect(text.substring(match.start, match.end), slice);
      controller.dispose();
    }
  });

  test('Case normalization preserves the identity-map branch', () {
    const source = 'İstanbul';
    final cased = foldForSearch(
      source,
      caseSensitive: false,
      foldToBaseLetters: false,
    );

    expect(cased.text, 'istanbul');
    expect(cased.text.length, source.length);
    for (var offset = 0; offset <= source.length; offset++) {
      expect(cased.sourceOffset(offset), offset);
      expect(cased.sourceEnd(offset), offset);
    }

    const expandedSource = 'İStraße';
    final folded = foldForSearch(
      expandedSource,
      caseSensitive: false,
      foldToBaseLetters: true,
    );
    expect(folded.text, 'istrasse');
    expect(folded.sourceOffset(5), 5);
    expect(folded.sourceOffset(6), 5);
    expect(folded.sourceEnd(7), 6);
    expect(folded.sourceEnd(folded.text.length), expandedSource.length);
  });

  testWidgets(
    'Text and query normalization is symmetric and respects case sensitivity',
    (tester) async {
      final reversed = FindInPageController()
        ..register(_TextSource('istanbul'));
      reversed.search('İstanbul', diacriticSensitive: true);
      await tester.pump();
      expect(reversed.matchCount, 1);
      expect(reversed.activeMatch!.start, 0);
      expect(reversed.activeMatch!.end, 8);
      reversed.dispose();

      final sensitive = FindInPageController()
        ..register(_TextSource('İstanbul'));
      sensitive.search(
        'istanbul',
        caseSensitive: true,
        diacriticSensitive: true,
      );
      await tester.pump();
      expect(sensitive.matchCount, 0);

      sensitive.search('İstanbul');
      await tester.pump();
      expect(sensitive.matchCount, 1);
      expect(sensitive.activeMatch!.start, 0);
      expect(sensitive.activeMatch!.end, 8);
      sensitive.dispose();
    },
  );

  testWidgets(
    'Explicit combining dots survive diacritic-sensitive folding',
    (tester) async {
      const dotted = 'i\u0307stanbul';
      final folded = foldForSearch(
        dotted,
        caseSensitive: false,
        foldToBaseLetters: false,
      );
      expect(folded.text, dotted);
      expect(folded.text.length, dotted.length);

      for (final (text, query) in [
        (dotted, 'istanbul'),
        ('istanbul', dotted),
      ]) {
        final controller = FindInPageController()..register(_TextSource(text));
        controller.search(query, diacriticSensitive: true);
        await tester.pump();
        expect(controller.matchCount, 0, reason: '$text / $query');
        controller.dispose();
      }
    },
  );

  testWidgets('Supplementary characters retain UTF-16 source offsets', (
    tester,
  ) async {
    const text = '😀İB';
    final controller = FindInPageController()..register(_TextSource(text));
    controller.search('b');
    await tester.pump();

    expect(controller.matchCount, 1);
    final match = controller.activeMatch!;
    expect(match.start, 3);
    expect(match.end, 4);
    expect(text.substring(match.start, match.end), 'B');
    controller.dispose();
  });

  testWidgets('FindableText renders the reported original-text highlight', (
    tester,
  ) async {
    const text = 'İstanbul ve İzmir';
    final controller = FindInPageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FindInPageScope(
            controller: controller,
            child: const FindableText(text),
          ),
        ),
      ),
    );

    controller.search('izmir');
    await tester.pump();

    expect(controller.matchCount, 1);
    expect(controller.activeMatch!.start, 12);
    expect(controller.activeMatch!.end, 17);

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(FindableText),
        matching: find.byType(RichText),
      ),
    );
    final segments = <(String, bool)>[];
    richText.text.visitChildren((span) {
      if (span case TextSpan(text: final segment?)) {
        segments.add((segment, span.style?.backgroundColor != null));
      }
      return true;
    });

    expect(richText.text.toPlainText(), text);
    expect(segments, [('İstanbul ve ', false), ('İzmir', true)]);
  });
}
