// Lowercasing is platform code. The Dart VM uses the simple case mappings,
// where no letter changes length. On the web lowercasing goes through
// JavaScript, which uses the full mappings, and there the dotted capital I
// becomes an i followed by a combining dot above. These pass on the VM with or
// without the offset map for that, so run them with --platform chrome too.

import 'package:find_in_page/src/text_fold.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a letter that lowercases to two code units keeps later offsets', () {
    const source = 'İSTANBUL';
    final folded = foldForSearch(
      source,
      caseSensitive: false,
      foldToBaseLetters: true,
    );

    // The dot above is a combining mark, so it folds away like any other.
    expect(folded.text, 'istanbul');
    expect(
      [for (var i = 0; i <= folded.text.length; i++) folded.sourceOffset(i)],
      [0, 1, 2, 3, 4, 5, 6, 7, 8],
    );
    expect(folded.sourceEnd(folded.text.length), source.length);
  });

  test('the same holds when base letters are kept', () {
    // Here the dot above stays in the folded text on the web, before a match
    // or inside one.
    const source = 'İzmir fair';
    final folded = foldForSearch(
      source,
      caseSensitive: false,
      foldToBaseLetters: false,
    );

    final fair = folded.text.indexOf('fair');
    expect(folded.sourceOffset(fair), 6);
    expect(folded.sourceEnd(fair + 'fair'.length), source.length);
    expect(folded.resumeAfter(source.length), folded.text.length);

    final needle = foldForSearch(
      'İzmir',
      caseSensitive: false,
      foldToBaseLetters: false,
    ).text;
    final izmir = folded.text.indexOf(needle);
    expect(folded.sourceOffset(izmir), 0);
    expect(folded.sourceEnd(izmir + needle.length), 5);
    expect(folded.resumeAfter(5), folded.text.indexOf(' '));
  });

  test('every code point leaves the letter after it in place', () {
    final misplaced = <String>[];
    for (var codePoint = 0; codePoint <= 0x10FFFF; codePoint++) {
      if (codePoint >= 0xD800 && codePoint <= 0xDFFF) continue;
      final letter = String.fromCharCode(codePoint);
      final source = '${letter}x';
      for (final foldToBaseLetters in const [true, false]) {
        final folded = foldForSearch(
          source,
          caseSensitive: false,
          foldToBaseLetters: foldToBaseLetters,
        );
        final x = folded.text.length - 1;
        if (folded.sourceOffset(x) != letter.length ||
            folded.sourceEnd(x + 1) != source.length) {
          misplaced.add('${_hex(codePoint)} '
              '${foldToBaseLetters ? 'folded' : 'cased'}');
        }
      }
    }
    expect(misplaced, isEmpty);
  });

  test('no code point lowercases to fewer code units than it has', () {
    // The fold takes a lowercase copy of the same length as one in which
    // every letter kept its offset. That is only true while no letter gets
    // shorter, since one that did could hide a letter that got longer.
    final shorter = <String>[];
    for (var codePoint = 0; codePoint <= 0x10FFFF; codePoint++) {
      if (codePoint >= 0xD800 && codePoint <= 0xDFFF) continue;
      final letter = String.fromCharCode(codePoint);
      if (letter.toLowerCase().length < letter.length) {
        shorter.add(_hex(codePoint));
      }
    }
    expect(shorter, isEmpty);
  });
}

String _hex(int codePoint) =>
    'U+${codePoint.toRadixString(16).toUpperCase().padLeft(4, '0')}';
