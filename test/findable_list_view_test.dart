import 'dart:math' as math;

import 'package:find_in_page/find_in_page.dart';
// ignore: deprecated_member_use
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
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

    testWidgets('reveals a match below the list\'s leading padding', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final rows = _rows()..[300] = 'needle far below the fold';

      await tester.pumpWidget(
        _app(
          FindInPageScope(
            controller: controller,
            child: FindableListView(
              itemCount: rows.length,
              itemExtent: 40,
              padding: const EdgeInsets.only(top: 100),
              scrollController: scrollController,
              findableTextOf: (index) => rows[index],
              itemBuilder: (context, index, matches, activeMatchIndex) =>
                  SizedBox(height: 40, child: Text(rows[index])),
            ),
          ),
        ),
      );
      controller.search('needle');
      await tester.pumpAndSettle();

      expect(scrollController.offset, 100 + 300 * 40 - 400 * 0.3);
      final row = tester.getRect(find.text('needle far below the fold'));
      final viewport = tester.getRect(find.byType(FindableListView));
      expect(row.top - viewport.top, closeTo(400 * 0.3, 0.001));
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

    /// A 300 by 400 list over [rows] whose row extents come from [extentOf].
    Widget sizedList(
      FindInPageController controller,
      ScrollController scrollController,
      List<String> rows,
      ItemExtentBuilder extentOf, {
      EdgeInsetsGeometry? padding,
    }) => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          height: 400,
          child: FindInPageScope(
            controller: controller,
            child: FindableListView(
              itemCount: rows.length,
              itemExtentBuilder: extentOf,
              padding: padding,
              scrollController: scrollController,
              findableTextOf: (index) => rows[index],
              itemBuilder: (context, index, matches, activeMatchIndex) =>
                  Text(rows[index]),
            ),
          ),
        ),
      ),
    );

    /// Searches for the only needle in [rows] and checks where its row
    /// lands.
    Future<void> expectRevealed(
      WidgetTester tester,
      List<String> rows,
      ItemExtentBuilder extentOf,
      int target,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      rows[target] = 'needle in row $target';
      await tester.pumpWidget(
        sizedList(controller, scrollController, rows, extentOf),
      );
      controller.search('needle');
      await tester.pumpAndSettle();

      const dimensions = SliverLayoutDimensions(
        scrollOffset: 0,
        precedingScrollExtent: 0,
        viewportMainAxisExtent: 400,
        crossAxisExtent: 300,
      );
      var rowStart = 0.0;
      var total = 0.0;
      for (var i = 0; i < rows.length; i++) {
        if (i == target) rowStart = total;
        total += extentOf(i, dimensions)!;
      }
      final expected = math.min(rowStart - 400 * 0.3, total - 400);
      expect(scrollController.offset, expected, reason: 'row $target');
      final row = tester.getRect(find.text('needle in row $target'));
      final viewport = tester.getRect(find.byType(FindableListView));
      expect(row.top - viewport.top, rowStart - expected);
      expect(row.bottom, lessThanOrEqualTo(viewport.bottom));
    }

    // Rows 450 to 499 are five times as tall as the ones before them, like
    // the latest messages of a chat that carry pictures. The list estimates
    // its extent from the short rows it has built and stops short of them.
    double tallTail(int index, SliverLayoutDimensions dimensions) =>
        index < 450 ? 40 : 200;

    for (final target in [455, 470, 499]) {
      testWidgets('reveals row $target past an estimate built from shorter '
          'rows', (tester) async {
        await expectRevealed(tester, _rows(), tallTail, target);
      });
    }

    testWidgets('a newer reveal takes over from one that is still aiming', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final rows = _rows()
        ..[100] = 'needle near'
        ..[470] = 'needle far';
      await tester.pumpWidget(
        sizedList(controller, scrollController, rows, tallTail),
      );
      controller.search('needle');
      await tester.pumpAndSettle();
      const nearOffset = 100 * 40 - 400 * 0.3;
      expect(scrollController.offset, nearOffset);

      // Row 470 takes more than one animation to reach. Halfway through
      // the first one, the user goes back to row 100.
      controller.next();
      await tester.pump();
      // The first frame of the animation, then 100 ms into it.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 100));
      controller.previous();
      await tester.pump();
      final atSwitch = scrollController.offset;
      expect(atSwitch, greaterThan(nearOffset));

      final offsets = <double>[];
      for (var i = 0; i < 200 && tester.binding.hasScheduledFrame; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        offsets.add(scrollController.offset);
      }
      // A replaced reveal that aims again restarts the animation each time
      // it does, and the list stalls where it was.
      expect(
        offsets[1],
        lessThan(atSwitch),
        reason: 'the reveal of row 470 aimed again after it was replaced',
      );
      for (var i = 1; i < offsets.length; i++) {
        expect(offsets[i], lessThanOrEqualTo(offsets[i - 1]), reason: '$i');
      }
      expect(scrollController.offset, nearOffset);
    });

    testWidgets('reveals the last row of a list whose extents alternate', (
      tester,
    ) async {
      await expectRevealed(tester, _rows(), extentOf, 499);
    });

    testWidgets('the reveal passes the builder the dimensions the list '
        'passes, padding included', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final calls = <(SchedulerPhase, SliverLayoutDimensions)>[];
      double recording(int index, SliverLayoutDimensions dimensions) {
        calls.add((SchedulerBinding.instance.schedulerPhase, dimensions));
        return extentOf(index, dimensions);
      }

      final rows = _rows()..[301] = 'needle far below the fold';
      await tester.pumpWidget(
        sizedList(
          controller,
          scrollController,
          rows,
          recording,
          padding: const EdgeInsets.fromLTRB(10, 100, 20, 30),
        ),
      );
      scrollController.jumpTo(1000);
      await tester.pump();
      // The list calls the builder during layout.
      final fromList = calls
          .lastWhere((call) => call.$1 == SchedulerPhase.persistentCallbacks)
          .$2;
      expect(
        fromList,
        const SliverLayoutDimensions(
          scrollOffset: 900,
          precedingScrollExtent: 100,
          viewportMainAxisExtent: 400,
          crossAxisExtent: 270,
        ),
      );

      calls.clear();
      controller.search('needle');
      await tester.pump();
      // The reveal runs after the frame, at the same scroll offset.
      final fromReveal = [
        for (final (phase, dimensions) in calls)
          if (phase == SchedulerPhase.postFrameCallbacks) dimensions,
      ];
      expect(fromReveal, isNotEmpty);
      expect(fromReveal.first, fromList);

      await tester.pumpAndSettle();
      // 100 of padding, then rows 0 to 300, which are 151 rows of 40 and 150
      // rows of 72.
      const rowStart = 100 + 151 * 40.0 + 150 * 72.0;
      expect(scrollController.offset, rowStart - 400 * 0.3);
      final row = tester.getRect(find.text('needle far below the fold'));
      final viewport = tester.getRect(find.byType(FindableListView));
      expect(row.top - viewport.top, closeTo(400 * 0.3, 0.001));
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

  group('the user takes the scroll during a reveal', () {
    /// A 300 by 400 list with a match in row 300, searched, and 60 ms into
    /// the animation that reveals it.
    Future<ScrollController> midReveal(
      WidgetTester tester, {
      required bool varied,
      int target = 300,
      ItemExtentBuilder? extentOf,
    }) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final rows = _rows()..[target] = 'needle';
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 400,
              child: FindableListView(
                findController: controller,
                itemCount: rows.length,
                itemExtent: varied ? null : 40,
                itemExtentBuilder: varied
                    ? extentOf ?? (index, _) => index.isEven ? 40 : 72
                    : null,
                scrollController: scrollController,
                findableTextOf: (index) => rows[index],
                itemBuilder: (context, index, matches, activeMatchIndex) =>
                    Text(rows[index]),
              ),
            ),
          ),
        ),
      );
      controller.search('needle');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 60));
      expect(scrollController.offset, greaterThan(0), reason: 'mid reveal');
      return scrollController;
    }

    for (final varied in [false, true]) {
      final kind = varied ? 'varied' : 'fixed';

      testWidgets('a mouse wheel leaves a $kind list where it scrolled to', (
        tester,
      ) async {
        final scrollController = await midReveal(tester, varied: varied);
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(pointer.hover(const Offset(150, 200)));
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -2000)));
        await tester.pump();
        final afterWheel = scrollController.offset;
        await tester.pumpAndSettle();
        expect(scrollController.offset, afterWheel);
      });

      testWidgets('a finger held on a $kind list keeps it still', (
        tester,
      ) async {
        final scrollController = await midReveal(tester, varied: varied);
        final gesture = await tester.startGesture(const Offset(150, 200));
        await tester.pump(const Duration(milliseconds: 16));
        final held = scrollController.offset;
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(scrollController.offset, held, reason: 'frame $i');
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(scrollController.offset, held);
      });

      testWidgets('a drag leaves a $kind list where it was dragged to', (
        tester,
      ) async {
        final scrollController = await midReveal(tester, varied: varied);
        final gesture = await tester.startGesture(const Offset(150, 200));
        for (var i = 0; i < 10; i++) {
          await gesture.moveBy(const Offset(0, 30));
          await tester.pump(const Duration(milliseconds: 16));
        }
        final dragged = scrollController.offset;
        await gesture.up();
        await tester.pumpAndSettle();
        expect(scrollController.offset, dragged);
      });

      testWidgets('an app jump to the end of a $kind list stays there', (
        tester,
      ) async {
        // A chat that jumps to its latest message while a match is being
        // revealed further up.
        final scrollController = await midReveal(tester, varied: varied);
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
        await tester.pumpAndSettle();
        // The estimate of a varied list settles once the last rows are
        // built, and the list stays at whatever end that is.
        expect(
          scrollController.offset,
          scrollController.position.maxScrollExtent,
        );
        expect(find.text('row 499'), findsOneWidget);
      });
    }

    testWidgets('an app jump in the frame one aim ends stops the next one', (
      tester,
    ) async {
      final scrollController = await midReveal(
        tester,
        varied: true,
        target: 470,
        extentOf: (index, _) => index < 450 ? 40 : 200,
      );
      final firstAim = math.min(
        450 * 40 + 20 * 200 - 400 * 0.3,
        scrollController.position.maxScrollExtent,
      );
      // The animation lands on the first aim during a frame. A callback the
      // app registers then runs after that frame's layout, before the reveal
      // aims again.
      var jumps = 0;
      scrollController.addListener(() {
        if (jumps == 0 && scrollController.offset == firstAim) {
          jumps++;
          SchedulerBinding.instance.addPostFrameCallback(
            (_) => scrollController.jumpTo(0),
          );
        }
      });
      await tester.pumpAndSettle();
      expect(jumps, 1);
      expect(scrollController.offset, 0);
    });

    testWidgets('a finger put down as one aim ends stops the next one', (
      tester,
    ) async {
      // Row 470 sits in rows five times as tall as the ones built at first,
      // and takes more than one aim to reach.
      final scrollController = await midReveal(
        tester,
        varied: true,
        target: 470,
        extentOf: (index, _) => index < 450 ? 40 : 200,
      );
      final firstAim = math.min(
        450 * 40 + 20 * 200 - 400 * 0.3,
        scrollController.position.maxScrollExtent,
      );
      for (var i = 0; i < 30 && scrollController.offset != firstAim; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scrollController.offset, firstAim, reason: 'the first aim');
      expect(firstAim, lessThan(450 * 40 + 20 * 200 - 400 * 0.3));

      final gesture = await tester.startGesture(const Offset(150, 200));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scrollController.offset, firstAim);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scrollController.offset, firstAim);
    });
  });

  group('leading padding in every direction', () {
    /// Reveals row 250 of a 400 by 400 list and returns how far its leading
    /// edge lands from the viewport's leading edge, along the scroll
    /// direction.
    Future<double> lead(
      WidgetTester tester, {
      required Axis axis,
      bool reverse = false,
      TextDirection direction = TextDirection.ltr,
      EdgeInsetsGeometry? padding,
      EdgeInsets mediaPadding = EdgeInsets.zero,
      bool varied = true,
    }) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      const target = 250;
      final rows = List.generate(500, (i) => i == target ? 'needle' : 'r$i');
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(padding: mediaPadding),
          child: Directionality(
            textDirection: direction,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                height: 400,
                child: FindableListView(
                  findController: controller,
                  itemCount: rows.length,
                  scrollDirection: axis,
                  reverse: reverse,
                  padding: padding,
                  itemExtent: varied ? null : 50,
                  itemExtentBuilder: varied
                      ? (index, _) => index.isEven ? 40 : 72
                      : null,
                  scrollController: scrollController,
                  findableTextOf: (index) => rows[index],
                  itemBuilder: (context, index, matches, activeMatchIndex) =>
                      Text(rows[index], key: ValueKey(index)),
                ),
              ),
            ),
          ),
        ),
      );
      controller.search('needle');
      await tester.pumpAndSettle();
      final row = tester.getRect(find.byKey(const ValueKey(target)));
      return switch (scrollController.position.axisDirection) {
        AxisDirection.down => row.top,
        AxisDirection.up => 400 - row.bottom,
        AxisDirection.right => row.left,
        AxisDirection.left => 400 - row.right,
      };
    }

    final cases = <String, Future<double> Function(WidgetTester)>{
      'reversed vertical, padding below and above': (tester) => lead(
        tester,
        axis: Axis.vertical,
        reverse: true,
        padding: const EdgeInsets.only(bottom: 100, top: 30),
      ),
      'horizontal, left to right': (tester) => lead(
        tester,
        axis: Axis.horizontal,
        padding: const EdgeInsets.only(left: 100, right: 30),
      ),
      'horizontal, right to left': (tester) => lead(
        tester,
        axis: Axis.horizontal,
        direction: TextDirection.rtl,
        padding: const EdgeInsetsDirectional.only(start: 100, end: 30),
      ),
      'reversed horizontal, left to right': (tester) => lead(
        tester,
        axis: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.only(right: 100, left: 30),
      ),
      'reversed vertical with a fixed extent': (tester) => lead(
        tester,
        axis: Axis.vertical,
        reverse: true,
        varied: false,
        padding: const EdgeInsets.only(bottom: 100, top: 30),
      ),
      'vertical, padding from MediaQuery': (tester) => lead(
        tester,
        axis: Axis.vertical,
        mediaPadding: const EdgeInsets.only(top: 50, bottom: 10),
      ),
      'horizontal, padding from MediaQuery': (tester) => lead(
        tester,
        axis: Axis.horizontal,
        mediaPadding: const EdgeInsets.only(left: 50, right: 10),
      ),
    };
    for (final MapEntry(key: name, value: run) in cases.entries) {
      testWidgets('$name lands the row at 0.3 of the viewport', (tester) async {
        expect(await run(tester), closeTo(400 * 0.3, 0.001));
      });
    }
  });
}
