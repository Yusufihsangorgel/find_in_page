import 'package:find_in_page/find_in_page.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(height: 400, child: child)),
);

/// 500 short rows; only a handful fit inside the 400px viewport used by
/// [_app], so almost all of them never get built.
List<String> _rows() => List.generate(500, (i) => 'row $i');

Widget _list(
  FindInPageController controller,
  List<String> rows, {
  ScrollController? scrollController,
}) => FindInPageScope(
  controller: controller,
  child: FindableListView(
    itemCount: rows.length,
    itemExtent: 40,
    scrollController: scrollController,
    findableTextOf: (index) => rows[index],
    itemBuilder: (context, index, matches, activeMatchIndex) =>
        SizedBox(height: 40, child: Text(rows[index])),
  ),
);

void main() {
  group('FindableListView', () {
    testWidgets('counts a match on an item that is never built', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final rows = _rows()..[480] = 'needle far below the fold';

      await tester.pumpWidget(_app(_list(controller, rows)));
      await tester.pump();

      // Row 480 is nowhere near the built/cache area of a 400px viewport
      // over 40px rows starting at the top.
      expect(find.text('needle far below the fold'), findsNothing);

      controller.search('needle');
      await tester.pump();

      expect(controller.matchCount, 1);
    });

    testWidgets('scrolling does not change the match count', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final rows = _rows()
        ..[10] = 'needle near the top'
        ..[480] = 'needle far below the fold';

      await tester.pumpWidget(
        _app(_list(controller, rows, scrollController: scrollController)),
      );
      controller.search('needle');
      await tester.pump();
      expect(controller.matchCount, 2);

      // Scroll far enough that row 10 unbuilds and a whole new set of rows
      // (nowhere near either match) builds and disposes in its place.
      scrollController.jumpTo(4000);
      await tester.pump();
      expect(controller.matchCount, 2);

      scrollController.jumpTo(12000);
      await tester.pump();
      expect(controller.matchCount, 2);

      scrollController.jumpTo(0);
      await tester.pump();
      expect(controller.matchCount, 2);
    });

    testWidgets('reveals an off-screen match by scrolling to its index', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final rows = _rows()..[480] = 'needle far below the fold';

      await tester.pumpWidget(
        _app(_list(controller, rows, scrollController: scrollController)),
      );
      expect(scrollController.offset, 0);

      controller.search('needle');
      await tester.pumpAndSettle();

      expect(scrollController.offset, greaterThan(0));
      expect(find.text('needle far below the fold'), findsOneWidget);
    });

    testWidgets('hands the active item its match offsets', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final rows = _rows()..[0] = 'a needle and another needle';

      List<FindMatch>? seenMatches;
      int? seenActiveIndex;
      await tester.pumpWidget(
        _app(
          FindInPageScope(
            controller: controller,
            child: FindableListView(
              itemCount: rows.length,
              itemExtent: 40,
              findableTextOf: (index) => rows[index],
              itemBuilder: (context, index, matches, activeMatchIndex) {
                if (index == 0) {
                  seenMatches = matches;
                  seenActiveIndex = activeMatchIndex;
                }
                return SizedBox(height: 40, child: Text(rows[index]));
              },
            ),
          ),
        ),
      );

      controller.search('needle');
      await tester.pump();

      expect(seenMatches, hasLength(2));
      expect(seenActiveIndex, 0);
    });

    testWidgets('growing and shrinking the backing list stays consistent', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      var rows = _rows()..[480] = 'needle far below the fold';

      Widget build(List<String> rows) => _app(_list(controller, rows));

      await tester.pumpWidget(build(rows));
      controller.search('needle');
      await tester.pump();
      expect(controller.matchCount, 1);

      // Shrink past the match: it should disappear from the count.
      rows = rows.sublist(0, 100);
      await tester.pumpWidget(build(rows));
      await tester.pump();
      expect(controller.matchCount, 0);

      // Grow back past where it used to be, with a fresh match.
      rows = List.generate(500, (i) => 'row $i')..[480] = 'needle again';
      await tester.pumpWidget(build(rows));
      await tester.pump();
      expect(controller.matchCount, 1);
    });

    testWidgets('unregisters its records on dispose', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final rows = _rows()..[480] = 'needle far below the fold';

      await tester.pumpWidget(_app(_list(controller, rows)));
      controller.search('needle');
      await tester.pump();
      expect(controller.matchCount, 1);

      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pump();
      expect(controller.matchCount, 0);
    });
  });

  group('FindableListView.itemExtentBuilder', () {
    double extentOf(int index, SliverLayoutDimensions dimensions) =>
        index.isEven ? 40 : 72;

    testWidgets('reveals an off-screen match at the summed extents of the rows '
        'before it', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final rows = _rows()..[301] = 'needle far below the fold';

      await tester.pumpWidget(
        _app(
          FindInPageScope(
            controller: controller,
            child: FindableListView(
              itemCount: rows.length,
              itemExtentBuilder: extentOf,
              scrollController: scrollController,
              findableTextOf: (index) => rows[index],
              itemBuilder: (context, index, matches, activeMatchIndex) =>
                  Text(rows[index]),
            ),
          ),
        ),
      );
      controller.search('needle');
      await tester.pumpAndSettle();

      // Rows 0 to 300: 151 even rows of 40 and 150 odd rows of 72.
      const rowStart = 151 * 40.0 + 150 * 72.0;
      expect(scrollController.offset, rowStart - 400 * 0.3);
      final row = tester.getRect(find.text('needle far below the fold'));
      final viewport = tester.getRect(find.byType(FindableListView));
      expect(row.top - viewport.top, closeTo(400 * 0.3, 0.001));
      expect(row.height, 72);
    });

    testWidgets('lays rows out at the extents the builder returns', (
      tester,
    ) async {
      final rows = _rows();
      await tester.pumpWidget(
        _app(
          FindableListView(
            itemCount: rows.length,
            itemExtentBuilder: extentOf,
            findableTextOf: (index) => rows[index],
            itemBuilder: (context, index, matches, activeMatchIndex) =>
                Text(rows[index]),
          ),
        ),
      );
      expect(tester.getSize(find.text('row 0')).height, 40);
      expect(tester.getSize(find.text('row 1')).height, 72);
      expect(
        tester.getTopLeft(find.text('row 3')).dy -
            tester.getTopLeft(find.text('row 0')).dy,
        40 + 72 + 40,
      );
    });

    test('exactly one of itemExtent and itemExtentBuilder is required', () {
      FindableListView build({double? extent, ItemExtentBuilder? builder}) =>
          FindableListView(
            itemCount: 1,
            itemExtent: extent,
            itemExtentBuilder: builder,
            findableTextOf: (index) => '',
            itemBuilder: (context, index, matches, activeMatchIndex) =>
                const SizedBox(),
          );
      expect(() => build(), throwsAssertionError);
      expect(() => build(extent: 40, builder: extentOf), throwsAssertionError);
      expect(build(extent: 40).itemExtent, 40);
      expect(build(builder: extentOf).itemExtentBuilder, isNotNull);
    });
  });
}
