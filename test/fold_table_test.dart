// The whole fold table, enumerated.
//
// The first version of base-letter folding shipped green with sixty-two tests
// passing while four of the five expansion pairs could not be found by their
// first half at all. The one test it had for expansions used the eszett, which
// folds to two of the same letter and so hid the bug: the second hit landed
// correctly and covered for the first, which was being discarded.
//
// Picking an example from a table leaves the rest of the table untested, and
// the example that gets picked is as likely as not to be the special one.
// These walk every entry instead.

import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const expansions = {
  'Æ': 'AE',
  'æ': 'ae',
  'Þ': 'TH',
  'þ': 'th',
  'ß': 'ss',
  'ẞ': 'SS',
  'Œ': 'OE',
  'œ': 'oe',
  'Ĳ': 'IJ',
  'ĳ': 'ij',
};

int count(String text, String query) {
  final c = FindInPageController()..register(_S(text));
  c.search(query);
  final n = c.matchCount;
  c.dispose();
  return n;
}

void main() {
  testWidgets('every expansion, every substring of what it folds to',
      (tester) async {
    final bad = <String>[];
    for (final e in expansions.entries) {
      final folded = e.value.toLowerCase();
      for (var i = 0; i < folded.length; i++) {
        for (var j = i + 1; j <= folded.length; j++) {
          final q = folded.substring(i, j);
          for (final wrap in ['%', 'x%', '%x', 'x%x']) {
            final text = wrap.replaceAll('%', e.key);
            if (count(text, q) == 0) bad.add('"$text" <- "$q"');
          }
        }
      }
    }
    // ignore: avoid_print
    print('SUBSTRING_MISS=${bad.length} ${bad.take(6)}');
    expect(bad, isEmpty);
  });

  testWidgets('adjacent, leading, trailing and all-expansion strings',
      (tester) async {
    final bad = <String>[];
    final keys = expansions.keys.toList();
    for (final a in keys) {
      for (final b in keys) {
        final text = '$a$b';
        final want = (expansions[a]! + expansions[b]!).toLowerCase();
        for (var i = 0; i < want.length; i++) {
          final q = want.substring(i, i + 1);
          if (count(text, q) == 0) bad.add('"$text" <- "$q"');
        }
      }
    }
    // ignore: avoid_print
    print('ADJACENT_MISS=${bad.length} ${bad.take(6)}');
    expect(bad, isEmpty);
  });

  testWidgets('an expanding character as the query finds itself',
      (tester) async {
    final bad = <String>[];
    for (final e in expansions.entries) {
      if (count('a${e.key}b', e.key) == 0) bad.add('${e.key} <- itself');
      if (count('a${e.key}b', e.value.toLowerCase()) == 0) {
        bad.add('${e.key} <- "${e.value.toLowerCase()}"');
      }
    }
    // ignore: avoid_print
    print('SELF_MISS=${bad.length} $bad');
    expect(bad, isEmpty);
  });

  testWidgets('a highlighted slice always contains the query once folded',
      (tester) async {
    // The offsets are what the overlay paints with. If a slice does not
    // contain what was searched for, the reader sees the wrong characters
    // lit up, which is worse than finding nothing.
    const alphabet = ['a', 's', 'ß', 'æ', 'é', 'x'];
    final texts = <String>[];
    for (final a in alphabet) {
      texts.add(a);
      for (final b in alphabet) {
        texts.add('$a$b');
        for (final c in alphabet) {
          texts.add('$a$b$c');
        }
      }
    }
    final queries = <String>['a', 's', 'ss', 'ae', 'e', 'as', 'sa', 'ß'];

    var checked = 0;
    final bad = <String>[];
    for (final text in texts) {
      for (final query in queries) {
        final c = FindInPageController()..register(_S(text));
        c.search(query);
        for (var i = 0; i < c.matchCount; i++) {
          final m = c.activeMatch!;
          final slice = text.substring(m.start, m.end);
          checked++;
          if (!_fold(slice).contains(_fold(query))) {
            bad.add('"\$text" <- "\$query" lit "\$slice"');
          }
          c.next();
        }
        c.dispose();
      }
    }
    // ignore: avoid_print
    print('INVARIANT checked=$checked violations=${bad.length} ${bad.take(5)}');
    expect(bad, isEmpty);
  });

  testWidgets('no two matches cover the same character', (tester) async {
    final bad = <String>[];
    for (final text in ['Weiß', 'ßß', 'Straße', 'ÆÆ', 'aßßa', 'ﬀ']) {
      for (final query in ['s', 'ss', 'a', 'e']) {
        final c = FindInPageController()..register(_S(text));
        c.search(query);
        var previousEnd = -1;
        for (var i = 0; i < c.matchCount; i++) {
          final m = c.activeMatch!;
          if (m.start < previousEnd) {
            bad.add('"\$text" <- "\$query" overlap at \${m.start}');
          }
          previousEnd = m.end;
          c.next();
        }
        c.dispose();
      }
    }
    // ignore: avoid_print
    print('OVERLAP=${bad.length} $bad');
    expect(bad, isEmpty);
  });
}

/// The same reduction the matcher uses, written out so the invariant is
/// checked against an independent copy rather than the code under test.
String _fold(String s) {
  const table = {
    'æ': 'ae',
    'þ': 'th',
    'ß': 'ss',
    'œ': 'oe',
    'ĳ': 'ij',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'á': 'a',
    'à': 'a',
  };
  final out = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    out.write(table[ch] ?? ch);
  }
  return out.toString();
}

class _S implements FindableSource {
  _S(this.findableText);
  @override
  final String findableText;
  @override
  BuildContext? get findableContext => null;
}
