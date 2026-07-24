import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:find_in_page/find_in_page.dart';

/// A source with no widget behind it, so the controller can be exercised
/// directly without building a page.
class _TextSource implements FindableSource {
  _TextSource(this.findableText);

  @override
  String findableText;

  @override
  BuildContext? get findableContext => null;
}

void main() {
  group('FindInPageController contract', () {
    testWidgets('case sensitivity is opt-in and sticky', (tester) async {
      final controller = FindInPageController()
        ..register(_TextSource('the cat sat'))
        ..register(_TextSource('CAT scan cataract'));

      controller.search('cat');
      await tester.pump();
      expect(controller.matchCount, 3, reason: 'cat, CAT and cataract');

      controller.search('cat', caseSensitive: true);
      await tester.pump();
      expect(controller.matchCount, 2, reason: 'CAT no longer matches');

      // Omitting the flag keeps the previous setting rather than resetting it.
      controller.search('cat');
      await tester.pump();
      expect(controller.matchCount, 2);
    });

    testWidgets('matches do not overlap', (tester) async {
      final controller = FindInPageController()..register(_TextSource('aaaa'));
      controller.search('aa');
      await tester.pump();
      expect(controller.matchCount, 2, reason: 'scanning resumes past a match');
    });

    testWidgets('offsets index the original text, not a folded copy',
        (tester) async {
      // Case-insensitive search lowercases the haystack to compare, so the
      // reported offsets must still slice the text the caller gave us —
      // including past an emoji, which is two UTF-16 units.
      const text = '🎉 café İstanbul cat here';
      final source = _TextSource(text);
      final controller = FindInPageController()..register(source);

      controller.search('cat');
      await tester.pump();
      expect(controller.matchCount, 1);

      final match = controller.activeMatch!;
      expect(text.substring(match.start, match.end), 'cat');
    });

    testWidgets('an empty or unmatched query clears the session',
        (tester) async {
      final controller = FindInPageController()
        ..register(_TextSource('the cat sat'));

      controller.search('cat');
      await tester.pump();
      expect(controller.matchCount, 1);

      controller.search('');
      await tester.pump();
      expect(controller.matchCount, 0);
      expect(controller.activeMatchIndex, isNull);

      controller.search('a query longer than the text itself is');
      await tester.pump();
      expect(controller.matchCount, 0);
      expect(controller.activeMatchIndex, isNull);
    });

    testWidgets('next and previous wrap around', (tester) async {
      final controller = FindInPageController()
        ..register(_TextSource('cat cat cat'));
      controller.search('cat');
      await tester.pump();
      expect(controller.matchCount, 3);
      expect(controller.activeMatchIndex, 0);

      controller
        ..next()
        ..next()
        ..next();
      expect(controller.activeMatchIndex, 0, reason: 'wrapped past the end');

      controller.previous();
      expect(controller.activeMatchIndex, 2, reason: 'wrapped past the start');
    });

    testWidgets('the active index does not go stale when matches disappear',
        (tester) async {
      final source = _TextSource('cat cat cat');
      final controller = FindInPageController()..register(source);
      controller.search('cat');
      await tester.pump();
      controller.next();
      expect(controller.activeMatchIndex, 1);

      source.findableText = 'nothing here now';
      controller.search('cat');
      await tester.pump();
      expect(controller.matchCount, 0);
      expect(controller.activeMatchIndex, isNull);
      expect(controller.activeMatch, isNull);
    });

    testWidgets('unregistering a source drops its matches', (tester) async {
      final source = _TextSource('the cat sat');
      final controller = FindInPageController()..register(source);
      controller.search('cat');
      await tester.pump();
      expect(controller.matchCount, 1);

      controller.unregister(source);
      controller.search('cat');
      await tester.pump();
      expect(controller.matchCount, 0);
    });
  });
}
