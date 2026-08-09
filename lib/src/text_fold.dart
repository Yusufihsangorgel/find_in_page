/// Folding a string to the form the matcher compares against, and the map
/// that takes an offset in that form back to the text the caller gave us.
library;

/// A folded copy of a string, plus the way back to the original's offsets.
final class FoldedText {
  const FoldedText(this.text, this._map);

  /// The text `indexOf` runs against.
  final String text;

  /// For every offset in [text], the offset in the original it came from,
  /// with one extra entry holding the original's length so that the end of a
  /// match at the end of the text has somewhere to land.
  ///
  /// Null when folding changed no character counts, which is the common case:
  /// plain ASCII folds to itself, and an accented letter usually folds to one
  /// letter. Offsets then already index the original and no lookup is needed.
  final List<int>? _map;

  /// The offset in the original text that folded [offset] came from.
  int sourceOffset(int offset) => _map == null ? offset : _map[offset];
}

/// Folds [source] into the form matching compares against.
///
/// Lowercases unless [caseSensitive], and reduces letters to their base form
/// unless [foldToBaseLetters] is false. See [FoldedText.sourceOffset] for
/// getting back to [source]'s own offsets.
FoldedText foldForSearch(
  String source, {
  required bool caseSensitive,
  required bool foldToBaseLetters,
}) {
  // Lowercasing never changes a string's UTF-16 length: no code point in
  // Unicode has a longer simple lowercase mapping than itself, and Dart uses
  // the simple mappings. Offsets in [cased] therefore still index [source],
  // and only the base letter fold below can move them.
  final cased = caseSensitive ? source : source.toLowerCase();
  if (!foldToBaseLetters) return FoldedText(cased, null);

  // Both stay null while the copy is still character-for-character identical,
  // so an all-ASCII page allocates neither.
  StringBuffer? folded;
  List<int>? map;

  for (var i = 0; i < cased.length; i++) {
    final unit = cased.codeUnitAt(i);
    final replacement = unit < _firstFoldable ? null : _replacementFor(unit);
    if (replacement == null) {
      folded?.writeCharCode(unit);
      map?.add(i);
      continue;
    }
    folded ??= StringBuffer(cased.substring(0, i));
    if (replacement.length != 1 && map == null) {
      // The first character that does not fold one-for-one. Everything before
      // it lined up, so seed the map with that identity run and track offsets
      // from here on.
      map = List<int>.generate(folded.length, (offset) => offset);
    }
    folded.write(replacement);
    for (var k = 0; k < replacement.length; k++) {
      map?.add(i);
    }
  }

  if (folded == null) return FoldedText(cased, null);
  map?.add(cased.length);
  return FoldedText(folded.toString(), map);
}

/// Below this every code unit folds to itself, which keeps ASCII off the
/// lookup entirely. Asserted against [_foldTable] where the table is built.
const int _firstFoldable = 0x00C0;

/// Combining marks, which a decomposed spelling puts after its base letter.
/// Dropping them is what makes the two spellings of `Mädchen` match.
const int _firstCombiningMark = 0x0300;
const int _lastCombiningMark = 0x036F;

String? _replacementFor(int unit) {
  if (unit >= _firstCombiningMark && unit <= _lastCombiningMark) return '';
  return _foldTable[unit];
}

/// Every character in Latin-1 Supplement and Latin Extended-A that is a
/// letter, mapped to the letters someone would type instead of it.
///
/// Keyed by the base letter so that a missing accent is visible as a gap in a
/// group rather than a wrong line in a list of pairs. Case is preserved, which
/// is what keeps `caseSensitive` and base letter folding independent of each
/// other: `É` folds to `E`, not to `e`.
const Map<String, String> _foldGroups = {
  'A': 'ÀÁÂÃÄÅĀĂĄ',
  'a': 'àáâãäåāăą',
  'C': 'ÇĆĈĊČ',
  'c': 'çćĉċč',
  'D': 'ÐĎĐ',
  'd': 'ðďđ',
  'E': 'ÈÉÊËĒĔĖĘĚ',
  'e': 'èéêëēĕėęě',
  'G': 'ĜĞĠĢ',
  'g': 'ĝğġģ',
  'H': 'ĤĦ',
  'h': 'ĥħ',
  'I': 'ÌÍÎÏĨĪĬĮİ',
  'i': 'ìíîïĩīĭįı',
  'J': 'Ĵ',
  'j': 'ĵ',
  'K': 'Ķ',
  'k': 'ķĸ',
  'L': 'ĹĻĽĿŁ',
  'l': 'ĺļľŀł',
  'N': 'ÑŃŅŇŊ',
  'n': 'ñńņňŉŋ',
  'O': 'ÒÓÔÕÖØŌŎŐ',
  'o': 'òóôõöøōŏő',
  'R': 'ŔŖŘ',
  'r': 'ŕŗř',
  'S': 'ŚŜŞŠ',
  's': 'śŝşšſ',
  'T': 'ŢŤŦ',
  't': 'ţťŧ',
  'U': 'ÙÚÛÜŨŪŬŮŰŲ',
  'u': 'ùúûüũūŭůűų',
  'W': 'Ŵ',
  'w': 'ŵ',
  'Y': 'ÝŶŸ',
  'y': 'ýÿŷ',
  'Z': 'ŹŻŽ',
  'z': 'źżž',
};

/// The characters that stand in for more than one letter.
///
/// These are the only entries that move offsets, and the reason a match found
/// in the folded copy can start or end inside a single original character.
const Map<String, String> _foldExpansions = {
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

final Map<int, String> _foldTable = _buildFoldTable();

Map<int, String> _buildFoldTable() {
  final table = <int, String>{};
  for (final entry in _foldGroups.entries) {
    for (final unit in entry.value.codeUnits) {
      table[unit] = entry.key;
    }
  }
  for (final entry in _foldExpansions.entries) {
    table[entry.key.codeUnits.single] = entry.value;
  }
  assert(
    table.keys.every((unit) => unit >= _firstFoldable),
    'the fast path skips every unit below _firstFoldable, so nothing may fold '
    'below it: ${table.keys.where((unit) => unit < _firstFoldable)}',
  );
  assert(
    _unfolded(table).isEmpty,
    'the documented range is Latin-1 Supplement and Latin Extended-A, and '
    'these letters in it have no fold: ${_unfolded(table)}',
  );
  return table;
}

/// Letters in the documented range that the table forgot, as hex code points.
///
/// A dropped character in a group above is otherwise invisible: the fold keeps
/// working for everything else and only that one letter quietly stops
/// matching.
List<String> _unfolded(Map<int, String> table) => [
      for (var unit = 0x00C0; unit <= 0x017F; unit++)
        if (unit != 0x00D7 && unit != 0x00F7 && !table.containsKey(unit))
          'U+${unit.toRadixString(16).toUpperCase().padLeft(4, '0')}',
    ];
