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

  group('base letter folding', () {
    testWidgets('folds diacritics, dotless and dotted i, and eszett',
        (tester) async {
      // Every pair is a word someone would actually type into the bar, typed
      // the way a keyboard without that letter produces it. The last two
      // pairs are ASCII: they are the positive control, so a matcher that is
      // broken outright fails here too instead of making the table look
      // meaningful.
      const pairs = <(String, String)>[
        ('IŞIK', 'isik'),
        ('Diyarbakır', 'diyarbakir'),
        ('Ähnlich', 'ahnlich'),
        ('Straße', 'strasse'),
        ('résumé', 'resume'),
        ('CAFÉ', 'cafe'),
        ('İSTANBUL', 'istanbul'),
        ('Hello World', 'hello'),
        ('MERHABA', 'merhaba'),
      ];

      for (final (text, query) in pairs) {
        final controller = FindInPageController()..register(_TextSource(text));
        controller.search(query);
        await tester.pump();
        expect(controller.matchCount, 1, reason: '"$query" in "$text"');
      }
    });

    testWidgets('offsets survive a fold that deletes code units',
        (tester) async {
      // The acute accent is written separately here, so the fold drops a code
      // unit and every later offset shifts left. Without a map back to the
      // original text, start would be 5 and the slice would read " ca".
      const text = 'cafe\u0301 cat';
      final controller = FindInPageController()..register(_TextSource(text));

      controller.search('cat');
      await tester.pump();
      expect(controller.matchCount, 1);

      final match = controller.activeMatch!;
      expect(match.start, 6);
      expect(text.substring(match.start, match.end), 'cat');
    });

    testWidgets('offsets survive a fold that adds code units', (tester) async {
      // The eszett folds to two letters, so every later offset shifts right.
      // Unmapped, this reports (8, 11) against a 10 unit string, which throws
      // out of substring rather than merely highlighting the wrong word.
      const text = 'Straße cat';
      final controller = FindInPageController()..register(_TextSource(text));

      controller.search('cat');
      await tester.pump();
      expect(controller.matchCount, 1);

      final match = controller.activeMatch!;
      expect(match.start, 7);
      expect(match.end, 10);
      expect(text.substring(match.start, match.end), 'cat');
    });

    testWidgets('a match inside one expanded letter highlights that letter',
        (tester) async {
      // "Weiß" folds to "weiss", so "s" hits at two folded offsets and both
      // of them live inside the one eszett. Reporting the character once, and
      // painting it, is the answer: dropping the hit finds nothing in a word
      // that plainly contains it, and keeping both counts one letter twice.
      const text = 'Weiß';
      final controller = FindInPageController()..register(_TextSource(text));

      controller.search('s');
      await tester.pump();
      expect(controller.matchCount, 1);
      expect(
          text.substring(
            controller.activeMatch!.start,
            controller.activeMatch!.end,
          ),
          'ß');
    });

    testWidgets('both halves of an expansion are findable', (tester) async {
      // Rounding the end of a match down to the letter it started in made the
      // first half of every expansion unfindable: "Æther" folds to "aether",
      // and searching "a" produced an end at or before its start, so the hit
      // was discarded and the word appeared not to contain an a at all.
      const pairs = {
        'Æther': ['a', 'e'],
        'þing': ['t', 'h'],
        'Œuvre': ['o', 'e'],
        'Ĳsland': ['i', 'j'],
      };
      for (final entry in pairs.entries) {
        for (final query in entry.value) {
          final controller = FindInPageController()
            ..register(_TextSource(entry.key));
          controller.search(query);
          await tester.pump();
          expect(controller.matchCount, greaterThan(0),
              reason: '${entry.key} contains $query once folded');
          controller.dispose();
        }
      }
    });

    testWidgets('a match ending inside an expansion covers it', (tester) async {
      // "Straße" folds to "strasse". A query ending on the first of the two
      // folded s characters used to highlight "Stra", stopping one character
      // short of the letter that made it match.
      const text = 'Straße';
      final controller = FindInPageController()..register(_TextSource(text));

      controller.search('stras');
      await tester.pump();
      expect(controller.matchCount, 1);
      expect(
          text.substring(
            controller.activeMatch!.start,
            controller.activeMatch!.end,
          ),
          'Straß');
    });

    testWidgets('a query that folds away matches nothing and terminates',
        (tester) async {
      // A lone combining accent is not an empty query, but it folds to one.
      // Searching for the empty string finds it at every offset without ever
      // advancing, so this hangs rather than fails when the guard is missing.
      final controller = FindInPageController()
        ..register(_TextSource('cafe\u0301 cat'));

      controller.search('\u0301');
      await tester.pump();
      expect(controller.matchCount, 0);
      expect(controller.activeMatchIndex, isNull);
    });

    testWidgets('a match running to the end of a folded text maps to the end',
        (tester) async {
      // The whole string is one match, so end comes from the entry one past
      // the last folded character. Off by one there reports 7 against a
      // 6 unit string.
      const text = 'Straße';
      final controller = FindInPageController()..register(_TextSource(text));

      controller.search('strasse');
      await tester.pump();
      expect(controller.matchCount, 1);

      final match = controller.activeMatch!;
      expect(match.start, 0);
      expect(match.end, 6);
      expect(text.substring(match.start, match.end), text);
    });

    testWidgets('a surrogate pair before an expansion keeps offsets aligned',
        (tester) async {
      // Two shifts in opposite directions do not cancel: the emoji is two
      // code units the fold leaves alone, the eszett is one that becomes two.
      const text = '🎉 Straße cat';
      final controller = FindInPageController()..register(_TextSource(text));

      controller.search('cat');
      await tester.pump();
      expect(controller.matchCount, 1);

      final match = controller.activeMatch!;
      expect(text.substring(match.start, match.end), 'cat');
    });

    testWidgets('NFC and NFD spellings of the same word both match',
        (tester) async {
      // These two look identical on screen and nobody chooses between them;
      // the editor, keyboard or paste buffer does. Escaped on purpose, so
      // saving this file cannot quietly normalise the distinction away.
      const composed = 'M\u00e4dchen'; // a with diaeresis, one code point
      const decomposed = 'Ma\u0308dchen'; // a, then a combining diaeresis
      expect(composed == decomposed, isFalse, reason: 'different encodings');

      for (final text in [composed, decomposed]) {
        final controller = FindInPageController()..register(_TextSource(text));
        controller.search('madchen');
        await tester.pump();
        expect(controller.matchCount, 1, reason: text.codeUnits.toString());
      }
    });

    testWidgets('diacriticSensitive: true restores exact matching',
        (tester) async {
      final controller = FindInPageController()
        ..register(_TextSource('r\u00e9sum\u00e9'));

      controller.search('resume', diacriticSensitive: true);
      await tester.pump();
      expect(controller.matchCount, 0, reason: 'the accents now count');

      controller.search('r\u00e9sum\u00e9');
      await tester.pump();
      expect(controller.matchCount, 1, reason: 'typed with the accents');
    });

    testWidgets('diacritic sensitivity is sticky like case sensitivity',
        (tester) async {
      final controller = FindInPageController()
        ..register(_TextSource('r\u00e9sum\u00e9 and resume'));

      controller.search('resume');
      await tester.pump();
      expect(controller.matchCount, 2, reason: 'folded, both spellings');

      controller.search('resume', diacriticSensitive: true);
      await tester.pump();
      expect(controller.matchCount, 1);

      // Omitting the flag keeps the previous setting rather than resetting it.
      controller.search('resume');
      await tester.pump();
      expect(controller.matchCount, 1);
    });

    testWidgets('case and diacritic sensitivity are independent axes',
        (tester) async {
      // Folding to a base letter must not also fold the case away: the two
      // flags answer different questions and a user can want either one.
      final controller = FindInPageController()
        ..register(_TextSource('CAF\u00c9'));

      controller.search('CAFE', caseSensitive: true);
      await tester.pump();
      expect(controller.matchCount, 1, reason: 'E is the base letter of E');

      controller.search('cafe');
      await tester.pump();
      expect(controller.matchCount, 0, reason: 'case sensitivity is sticky');
    });

    testWidgets(
        'folding preserves case sensitivity and documented range boundaries',
        (tester) async {
      const istanbul = 'İSTANBUL i\u0307stanbul';
      final controller = FindInPageController()
        ..register(_TextSource(istanbul));
      addTearDown(controller.dispose);

      controller.search(
        'ISTANBUL',
        caseSensitive: true,
        diacriticSensitive: false,
      );
      await tester.pump();
      expect(controller.matchCount, 1);
      expect(
        istanbul.substring(
          controller.activeMatch!.start,
          controller.activeMatch!.end,
        ),
        'İSTANBUL',
      );

      controller.search('ISTANBUL', diacriticSensitive: true);
      await tester.pump();
      expect(controller.matchCount, 0);

      controller.search('İSTANBUL');
      await tester.pump();
      expect(controller.matchCount, 1);

      const outsideTable = <(String, String)>[
        ('ǒ', 'o'),
        ('ạ', 'a'),
        ('ά', 'α'),
        ('a\u1AB0b', 'ab'),
      ];
      for (final (text, query) in outsideTable) {
        final boundaryController = FindInPageController()
          ..register(_TextSource(text));
        boundaryController.search(query);
        await tester.pump();
        expect(
          boundaryController.matchCount,
          0,
          reason: '$text remains outside the base-letter table',
        );
        boundaryController.dispose();
      }

      const decomposed = 'a\u0323';
      final combiningController = FindInPageController()
        ..register(_TextSource(decomposed));
      combiningController.search('a');
      await tester.pump();
      expect(combiningController.matchCount, 1);
      expect(
        decomposed.substring(
          combiningController.activeMatch!.start,
          combiningController.activeMatch!.end,
        ),
        decomposed,
      );
      combiningController.dispose();

      for (final text in ['ǒ', 'ạ', 'ά', '\u1AB0']) {
        final identityController = FindInPageController()
          ..register(_TextSource(text));
        identityController.search(text, caseSensitive: true);
        await tester.pump();
        expect(
          identityController.matchCount,
          1,
          reason: 'identical unsupported text remains searchable',
        );
        identityController.dispose();
      }
    });

    testWidgets(
        'expanded matches preserve UTF-16 offsets after ZWJ and flag prefixes',
        (tester) async {
      const text = '👩‍💻 🇹🇷 Æ';
      final controller = FindInPageController()..register(_TextSource(text));
      addTearDown(controller.dispose);

      for (final query in ['e', 'ae']) {
        controller.search(query);
        await tester.pump();

        expect(controller.matchCount, 1, reason: 'query: $query');
        final match = controller.activeMatch!;
        expect(match.start, 11, reason: 'query: $query');
        expect(match.end, 12, reason: 'query: $query');
        expect(
          text.substring(match.start, match.end),
          'Æ',
          reason: 'query: $query',
        );
      }
    });
  });
}
