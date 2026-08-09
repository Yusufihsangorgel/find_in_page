// Draws doc/lazy-list.svg from match counts measured while scrolling.
//
//   flutter test tool/lazy_list_figure.dart
//   rsvg-convert -w 1600 doc/lazy-list.svg -o doc/lazy-list.png
//
// `tool/lazy_list_figure.sh` runs both and quantises the result.
//
// The figure is the argument for FindableListView. Two trees hold the same
// 500 rows at the same fixed extent and differ in one thing: who tells the
// controller a row exists. Both are scrolled to the same 50 offsets, and
// every number in the drawing is a matchCount read at one of them. Nothing
// here is typed in by hand, and the expectations below refuse to write the
// file if the two arms stop disagreeing.
//
// Kept outside test/ on purpose. `flutter test` with no path walks only
// test/, and CI has no reason to spend time rendering documentation.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rows in the backing list.
const _rowCount = 500;

/// Height of one row. `FindableListView` requires a fixed extent, and the
/// plain list is given the same one to keep layout identical across the two
/// arms. The only variable left is which rows the controller was told about.
const _itemExtent = 40.0;

/// Height of the viewport. Ten rows fit; a build and cache area of roughly
/// two dozen is what a plain `ListView.builder` therefore has to search.
const _viewport = 400.0;

/// Half-open row ranges holding the query. Clustered rather than spread
/// evenly, the way a term clusters in a document. The distribution is a
/// fixture; what the find bar makes of it is measured.
const _clusters = [(8, 14), (120, 127), (250, 251), (300, 310), (470, 489)];

const _query = 'timeout';

/// Scroll positions read in both arms, from the top of the list to the
/// bottom.
const _samples = 50;

final _output = File('doc/lazy-list.svg');

void main() {
  testWidgets('measures the lazy-list figure', (tester) async {
    final rows = _rows();
    final total = _occurrences(rows);
    final offsets = _offsets();

    final plain = await _sweepPlain(tester, rows, offsets);
    final lazy = await _sweepLazy(tester, rows, offsets);

    final peak = plain.reduce(math.max);
    expect(total, greaterThan(0), reason: 'the fixture must hold matches');
    expect(lazy, everyElement(total),
        reason: 'FindableListView claims a count that does not move while '
            'you scroll, and the figure says so');
    expect(plain.toSet().length, greaterThan(1),
        reason: 'without drift in the plain arm the figure has no subject');
    expect(peak, lessThan(total),
        reason: 'the plain arm must never hold the whole list at once');

    _output.writeAsStringSync(_svg(offsets, plain, lazy, total));

    final low = plain.reduce(math.min);
    stdout.writeln('rows              $_rowCount');
    stdout.writeln('matches in data   $total');
    stdout.writeln('positions read    ${offsets.length}');
    stdout.writeln('ListView.builder  $low..$peak, reading $low at '
        '${plain.where((count) => count == low).length} positions');
    stdout.writeln('FindableListView  ${lazy.toSet().single} everywhere');
    stdout.writeln('wrote ${_output.path}: ${_output.lengthSync()} bytes');
  });
}

/// The backing list: log lines, with the query in the [_clusters] rows.
List<String> _rows() {
  final rows = [
    for (var i = 0; i < _rowCount; i++)
      'request $i finished in ${8 + i % 40}ms',
  ];
  for (final (start, end) in _clusters) {
    for (var i = start; i < end; i++) {
      rows[i] = 'request $i gave up: upstream $_query after 30s';
    }
  }
  return rows;
}

/// How many times the query occurs in [rows], counted the way
/// `FindInPageController` counts it. This is the independent truth the
/// measured totals are checked against.
int _occurrences(List<String> rows) {
  final needle = _query.toLowerCase();
  var count = 0;
  for (final row in rows) {
    final haystack = row.toLowerCase();
    var offset = 0;
    while (true) {
      final index = haystack.indexOf(needle, offset);
      if (index < 0) break;
      count++;
      offset = index + needle.length;
    }
  }
  return count;
}

List<double> _offsets() {
  final maxScroll = _rowCount * _itemExtent - _viewport;
  return [
    for (var i = 0; i < _samples; i++) maxScroll * i / (_samples - 1),
  ];
}

/// A `ListView.builder` of `FindableText`, which is what the README's lazy
/// list section is about: a row only registers while it is built.
Future<List<int>> _sweepPlain(
  WidgetTester tester,
  List<String> rows,
  List<double> offsets,
) async {
  final controller = FindInPageController();
  addTearDown(controller.dispose);
  final scroll = ScrollController();
  addTearDown(scroll.dispose);

  await tester.pumpWidget(_app(
    controller,
    ListView.builder(
      controller: scroll,
      itemCount: rows.length,
      itemExtent: _itemExtent,
      itemBuilder: (context, index) => SizedBox(
        height: _itemExtent,
        child: FindableText(rows[index]),
      ),
    ),
  ));
  return _sweep(tester, controller, scroll, offsets);
}

/// The same rows through `FindableListView`, which reads every row's text up
/// front instead of waiting for it to be built.
Future<List<int>> _sweepLazy(
  WidgetTester tester,
  List<String> rows,
  List<double> offsets,
) async {
  final controller = FindInPageController();
  addTearDown(controller.dispose);
  final scroll = ScrollController();
  addTearDown(scroll.dispose);

  // Tear the previous arm down first so its rows unregister before this one
  // starts counting.
  await tester.pumpWidget(const SizedBox());
  await tester.pump();

  await tester.pumpWidget(_app(
    controller,
    FindableListView(
      itemCount: rows.length,
      itemExtent: _itemExtent,
      scrollController: scroll,
      findableTextOf: (index) => rows[index],
      itemBuilder: (context, index, matches, activeMatchIndex) => SizedBox(
        height: _itemExtent,
        child: Text(rows[index]),
      ),
    ),
  ));
  return _sweep(tester, controller, scroll, offsets);
}

Widget _app(FindInPageController controller, Widget list) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SizedBox(
          height: _viewport,
          child: FindInPageScope(
            controller: controller,
            showBar: false,
            child: list,
          ),
        ),
      ),
    );

/// Reads `matchCount` at every offset.
///
/// The query is cleared before each jump so that the rows built at the new
/// offset register while nothing is being searched; `search` then recomputes
/// synchronously over exactly the sources the controller holds there.
Future<List<int>> _sweep(
  WidgetTester tester,
  FindInPageController controller,
  ScrollController scroll,
  List<double> offsets,
) async {
  final counts = <int>[];
  for (final offset in offsets) {
    controller.clearSearch();
    await tester.pump();
    scroll.jumpTo(offset);
    await tester.pump();
    await tester.pump();
    // Revealing an active match animates the viewport. Both arms have to be
    // read at the same places or the two curves are not comparable.
    expect(scroll.offset, moreOrLessEquals(offset, epsilon: 0.5),
        reason: 'the sweep landed somewhere other than the offset it asked '
            'for; this reading belongs to a different position');
    controller.search(_query);
    counts.add(controller.matchCount);
  }
  return counts;
}

String _svg(
  List<double> offsets,
  List<int> plain,
  List<int> lazy,
  int total,
) {
  const w = 900.0, h = 452.0;
  const left = 88.0, right = 34.0, top = 92.0, bottom = 120.0;
  const plotW = w - left - right, plotH = h - top - bottom;
  final n = plain.length;

  double x(int i) => left + plotW * i / (n - 1);
  double y(num count) => top + plotH - plotH * count / total;

  String line(List<int> series) => [
        for (var i = 0; i < n; i++)
          '${i == 0 ? 'M' : 'L'} ${x(i).toStringAsFixed(1)} '
              '${y(series[i]).toStringAsFixed(1)}',
      ].join(' ');

  final step = total <= 20 ? 5 : (total <= 60 ? 10 : 20);
  final grid = StringBuffer();
  for (var v = 0; v <= total - step ~/ 2; v += step) {
    final gy = y(v).toStringAsFixed(1);
    grid.writeln('<line x1="$left" y1="$gy" x2="${w - right}" y2="$gy" '
        'stroke="#e3e6ea" stroke-width="1"/>');
    grid.writeln('<text x="${left - 12}" y="${y(v) + 4}" text-anchor="end" '
        'font-size="12" fill="#6b7280">$v</text>');
  }
  // The total sits on the axis as well as on the line.
  grid.writeln('<text x="${left - 12}" y="${y(total) + 4}" text-anchor="end" '
      'font-size="12" font-weight="600" fill="#2563eb">$total</text>');

  final ticks = [
    for (var i = 0; i < n; i++)
      if (i % 10 == 0 || i == n - 1)
        '<text x="${x(i).toStringAsFixed(1)}" y="${top + plotH + 24}" '
            'text-anchor="middle" font-size="12" fill="#6b7280">'
            '${(offsets[i] / _itemExtent).round()}</text>',
  ].join('\n');

  final peak = plain.reduce(math.max);
  final low = plain.reduce(math.min);
  final peakAt = plain.indexOf(peak);
  final peakRight = peakAt > n ~/ 2;
  final lowCount = plain.where((count) => count == low).length;

  // The band between what the list holds and what the plain arm could see.
  final gap = StringBuffer(line(plain))
    ..write(' L ${x(n - 1).toStringAsFixed(1)} ${y(total).toStringAsFixed(1)}')
    ..write(' L ${x(0).toStringAsFixed(1)} ${y(total).toStringAsFixed(1)} Z');

  return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w.toInt()} ${h.toInt()}"
     font-family="-apple-system, Segoe UI, Roboto, sans-serif">
<rect width="100%" height="100%" fill="#ffffff"/>
<text x="$left" y="38" font-size="18" font-weight="600" fill="#111827">
  Scrolling a $_rowCount-row list that holds $total matches
</text>
<text x="$left" y="62" font-size="13" fill="#6b7280">
  the same rows and the same query in both, counted at $n scroll positions
</text>
<path d="$gap" fill="#fee2e2" stroke="none"/>
$grid
<line x1="$left" y1="${top + plotH}" x2="${w - right}" y2="${top + plotH}"
      stroke="#9ca3af" stroke-width="1"/>
<path d="${line(lazy)}" fill="none" stroke="#2563eb" stroke-width="2.5"/>
<path d="${line(plain)}" fill="none" stroke="#dc2626" stroke-width="2.5"/>
<text x="${left + 14}" y="${y(total) + 22}" font-size="13" font-weight="600"
      fill="#2563eb">FindableListView &#183; $total, wherever you are</text>
<text x="${(peakRight ? x(peakAt) - 10 : x(peakAt) + 10).toStringAsFixed(1)}"
      y="${(y(peak) - 12).toStringAsFixed(1)}"
      text-anchor="${peakRight ? 'end' : 'start'}" font-size="13"
      font-weight="600" fill="#dc2626">
  ListView.builder + FindableText &#183; never above $peak
</text>
$ticks
<text x="${left + plotW / 2}" y="${top + plotH + 48}" text-anchor="middle"
      font-size="12" fill="#6b7280">row at the top of the viewport</text>
<text x="22" y="${top + plotH / 2}" font-size="12" fill="#6b7280"
      transform="rotate(-90 22 ${top + plotH / 2})" text-anchor="middle">
  matches the find bar reported
</text>
<rect x="$left" y="${h - 62}" width="$plotW" height="46" rx="8"
      fill="#f9fafb" stroke="#e5e7eb"/>
<text x="${left + 18}" y="${h - 40}" font-size="13" fill="#b91c1c">
  a row registers while it is built, and the count moves with the viewport:
  $low to $peak here, and $low at $lowCount of the $n positions
</text>
<text x="${left + 18}" y="${h - 22}" font-size="13" fill="#6b7280">
  shaded &#183; matches in the list that the count left out
</text>
</svg>
''';
}
