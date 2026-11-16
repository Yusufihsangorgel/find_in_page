import 'dart:math' as math;

import 'package:find_in_page/find_in_page.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// A `FindableText` in a scroll view that does not scroll implicitly.
///
/// `RenderObject.showOnScreen` passes over a `PageView` and a scroll view
/// under `NeverScrollableScrollPhysics`. The user cannot scroll the second at
/// all. `FindableText` moves both until the match is in view, as
/// `Scrollable.ensureVisible` did in 2.4.
void main() {
  // With allowImplicitScrolling, showOnScreen scrolls the PageView only until
  // the match shows, and the view then settles on the nearest page.
  for (final implicit in [false, true]) {
    final name = implicit ? ', with allowImplicitScrolling' : '';
    testWidgets('turns a PageView to the page holding the match$name', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = FindInPageController();
      final pages = PageController();
      addTearDown(controller.dispose);
      addTearDown(pages.dispose);

      const needles = {1, 3};
      final changed = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: controller,
            child: Scaffold(
              body: PageView(
                controller: pages,
                allowImplicitScrolling: implicit,
                onPageChanged: changed.add,
                children: [
                  for (var i = 0; i < 4; i++)
                    _KeptAlive(
                      // The match ends in the first half of its page.
                      // Scrolling only until it shows would stop short of half
                      // a page, and the PageView would settle back on the one
                      // before.
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: FindableText(
                            needles.contains(i) ? 'needle $i' : 'page $i',
                            key: ValueKey(i),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      // A page is built once it has been shown, and kept after that, as tabs
      // a user has opened are.
      for (final page in [1, 2, 3, 0]) {
        pages.jumpToPage(page);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      controller.open();
      await tester.pumpAndSettle();
      final view = tester.getRect(find.byType(PageView));

      Future<void> step(void Function() move, String name) async {
        move();
        await tester.pumpAndSettle();
        final match = controller.activeMatch!;
        final page = int.parse(match.source.findableText.split(' ')[1]);
        expect(pages.page, page, reason: name);
        // The app hears of the new page as it would after a swipe.
        expect(changed.last, page, reason: name);
        final rect = _matchRect(tester, ValueKey(page), match);
        expect(_inside(rect, view), isTrue, reason: '$name: $rect');
      }

      await step(() => controller.search('needle'), 'search, page 1');
      await step(controller.next, 'next, page 3');
      await step(controller.next, 'next wraps to page 1');
    });
  }

  // A match near the top of the page on screen stays under the bar. Moving
  // the view toward it ends on that same page again, after a visible jump.
  for (final implicit in [false, true]) {
    final name = implicit ? ', with allowImplicitScrolling' : '';
    testWidgets('keeps a vertical PageView on its page$name', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = FindInPageController();
      final pages = PageController(initialPage: 1);
      addTearDown(controller.dispose);
      addTearDown(pages.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: controller,
            child: Scaffold(
              body: PageView(
                controller: pages,
                scrollDirection: Axis.vertical,
                allowImplicitScrolling: implicit,
                children: [
                  for (var i = 0; i < 3; i++)
                    Align(
                      alignment: AlignmentDirectional.topStart,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        child: FindableText(i == 1 ? 'needle $i' : 'page $i'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      controller.open();
      await tester.pumpAndSettle();
      final start = pages.position.pixels;
      final offsets = <double>[];
      pages.addListener(() => offsets.add(pages.position.pixels));

      controller.search('needle');
      await tester.pumpAndSettle();
      expect(pages.page, 1);
      // With allowImplicitScrolling, showOnScreen still nudges the view by
      // the bar's margin before it settles back.
      final nudge = implicit ? 80.0 : 0.0;
      for (final offset in offsets) {
        expect(offset, greaterThanOrEqualTo(start - nudge - 0.5));
      }
    });
  }

  // A scroll view inside a tab or a page brings the match inside its own
  // bounds. The tab or the page around it stays where it is.
  testWidgets('keeps a TabBarView on the tab holding a sideways row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = FindInPageController();
    final tabs = TabController(length: 2, vsync: tester);
    final row = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(tabs.dispose);
    addTearDown(row.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: FindInPageScope(
          controller: controller,
          child: Scaffold(
            body: TabBarView(
              controller: tabs,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SingleChildScrollView(
                    controller: row,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < 30; i++)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: FindableText(
                              i == 25 ? 'chip needle' : 'chip $i',
                              key: ValueKey(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Text('second tab'),
              ],
            ),
          ),
        ),
      ),
    );
    controller.open();
    await tester.pumpAndSettle();
    final view = tester.getRect(find.byType(TabBarView));

    controller.search('needle');
    await tester.pumpAndSettle();
    expect(tabs.index, 0);
    expect(row.offset, greaterThan(0));
    final match = controller.activeMatch!;
    final rect = _matchRect(tester, const ValueKey(25), match);
    expect(_inside(rect, view), isTrue, reason: '$rect');
  });

  for (final implicit in [false, true]) {
    final name = implicit ? ', with allowImplicitScrolling' : '';
    testWidgets('keeps a vertical PageView on the page holding a list$name', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = FindInPageController();
      final pages = PageController(initialPage: 1);
      final list = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(pages.dispose);
      addTearDown(list.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: controller,
            child: Scaffold(
              body: PageView(
                controller: pages,
                scrollDirection: Axis.vertical,
                allowImplicitScrolling: implicit,
                children: [
                  const Text('page 0'),
                  SingleChildScrollView(
                    controller: list,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 1; i <= 100; i++)
                          FindableText(
                            i == 70 ? 'line $i needle' : 'line $i',
                            key: ValueKey(i),
                          ),
                      ],
                    ),
                  ),
                  const Text('page 2'),
                ],
              ),
            ),
          ),
        ),
      );
      controller.open();
      await tester.pumpAndSettle();
      final view = tester.getRect(find.byType(PageView));

      controller.search('needle');
      await tester.pumpAndSettle();
      expect(pages.page, 1);
      expect(list.offset, greaterThan(0));
      final match = controller.activeMatch!;
      final rect = _matchRect(tester, const ValueKey(70), match);
      expect(_inside(rect, view), isTrue, reason: '$rect');
    });
  }

  // A table scrolls along both axes. Its cell off to the right is brought
  // inside it, and the tab around it stays.
  testWidgets('keeps a TabBarView on the tab holding a table', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = FindInPageController();
    final tabs = TabController(length: 2, vsync: tester);
    addTearDown(controller.dispose);
    addTearDown(tabs.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: FindInPageScope(
          controller: controller,
          child: Scaffold(
            body: TabBarView(
              controller: tabs,
              children: [
                _Grid(
                  delegate: TwoDimensionalChildBuilderDelegate(
                    maxXIndex: 9,
                    maxYIndex: 9,
                    builder: (context, cell) => Center(
                      child: FindableText(
                        cell.xIndex == 7 && cell.yIndex == 1
                            ? 'cell needle'
                            : 'cell ${cell.xIndex} ${cell.yIndex}',
                        key: ValueKey((cell.xIndex, cell.yIndex)),
                      ),
                    ),
                  ),
                ),
                const Text('second tab'),
              ],
            ),
          ),
        ),
      ),
    );
    controller.open();
    await tester.pumpAndSettle();
    final view = tester.getRect(find.byType(TabBarView));

    controller.search('needle');
    await tester.pumpAndSettle();
    expect(tabs.index, 0);
    final match = controller.activeMatch!;
    final rect = _matchRect(tester, const ValueKey((7, 1)), match);
    expect(_inside(rect, view), isTrue, reason: '$rect');
  });

  testWidgets('scrolls a view under NeverScrollableScrollPhysics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = FindInPageController();
    final scroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);

    const needles = {100, 103, 170};
    await tester.pumpWidget(
      MaterialApp(
        home: FindInPageScope(
          controller: controller,
          child: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 1; i <= 200; i++)
                    FindableText(
                      needles.contains(i) ? 'line $i needle' : 'line $i',
                      key: ValueKey(i),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    controller.open();
    await tester.pumpAndSettle();
    final bar = tester.getRect(find.byType(FindBar));
    final body = tester.getRect(find.byType(SingleChildScrollView));

    Future<Rect> step(void Function() move, String name) async {
      move();
      await tester.pumpAndSettle();
      final match = controller.activeMatch!;
      final line = int.parse(match.source.findableText.split(' ')[1]);
      final rect = _matchRect(tester, ValueKey(line), match);
      expect(_inside(rect, body), isTrue, reason: '$name: $rect');
      expect(rect.overlaps(bar), isFalse, reason: '$name: $rect $bar');
      return rect;
    }

    // Moved, the match lands in the middle.
    var rect = await step(() => controller.search('needle'), 'line 100');
    expect(rect.center.dy, closeTo(body.center.dy, 0.5));

    // Three lines further down is already in view. Nothing moves.
    final offset = scroll.offset;
    await step(controller.next, 'line 103');
    expect(scroll.offset, offset, reason: 'line 103 was in view');

    rect = await step(controller.next, 'line 170');
    expect(rect.center.dy, closeTo(body.center.dy, 0.5));
    rect = await step(controller.previous, 'line 103 again');
    expect(rect.center.dy, closeTo(body.center.dy, 0.5));

    // On screen but under the bar counts as out of view.
    scroll.jumpTo(scroll.offset + rect.top - bar.top);
    await tester.pump();
    rect = await step(
      () => controller.selectMatch(1),
      'line 103 under the bar',
    );
    expect(rect.center.dy, closeTo(body.center.dy, 0.5));
  });

  // The margin above and below a match reaches past a sideways row. The view
  // around the row still keeps that margin clear of the bar.
  testWidgets('keeps a sideways row clear of the bar in a view under '
      'NeverScrollableScrollPhysics', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = FindInPageController();
    final scroll = ScrollController();
    final row = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    addTearDown(row.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: FindInPageScope(
          controller: controller,
          child: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                children: [
                  const SizedBox(height: 1000),
                  SingleChildScrollView(
                    controller: row,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < 30; i++)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: FindableText(
                              i == 25 ? 'chip needle' : 'chip $i',
                              key: ValueKey(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2000),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    controller.open();
    await tester.pumpAndSettle();
    // The row starts under the bar.
    scroll.jumpTo(990);
    await tester.pumpAndSettle();
    final bar = tester.getRect(find.byType(FindBar));
    final body = tester.getRect(find.byType(SingleChildScrollView).first);
    expect(
      tester.getRect(find.byKey(const ValueKey(0))).top,
      lessThan(bar.bottom),
    );

    controller.search('needle');
    await tester.pumpAndSettle();
    expect(row.offset, greaterThan(0));
    final match = controller.activeMatch!;
    final rect = _matchRect(tester, const ValueKey(25), match);
    expect(_inside(rect, body), isTrue, reason: '$rect');
    expect(rect.overlaps(bar), isFalse, reason: '$rect $bar');
  });
}

/// Keeps its page built after the `PageView` scrolls away from it.
class _KeptAlive extends StatefulWidget {
  const _KeptAlive({required this.child});

  final Widget child;

  @override
  State<_KeptAlive> createState() => _KeptAliveState();
}

class _KeptAliveState extends State<_KeptAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// A grid of 200 pixel cells that scrolls along both axes, the smallest
/// two-dimensional scroll view the framework lets a test build. It builds
/// every cell, as a short table would.
class _Grid extends TwoDimensionalScrollView {
  const _Grid({required super.delegate});

  @override
  Widget buildViewport(
    BuildContext context,
    ViewportOffset verticalOffset,
    ViewportOffset horizontalOffset,
  ) => _GridViewport(
    horizontalOffset: horizontalOffset,
    horizontalAxisDirection: horizontalDetails.direction,
    verticalOffset: verticalOffset,
    verticalAxisDirection: verticalDetails.direction,
    mainAxis: mainAxis,
    delegate: delegate as TwoDimensionalChildBuilderDelegate,
  );
}

class _GridViewport extends TwoDimensionalViewport {
  const _GridViewport({
    required super.verticalOffset,
    required super.verticalAxisDirection,
    required super.horizontalOffset,
    required super.horizontalAxisDirection,
    required TwoDimensionalChildBuilderDelegate super.delegate,
    required super.mainAxis,
  });

  @override
  RenderTwoDimensionalViewport createRenderObject(BuildContext context) =>
      _RenderGrid(
        horizontalOffset: horizontalOffset,
        horizontalAxisDirection: horizontalAxisDirection,
        verticalOffset: verticalOffset,
        verticalAxisDirection: verticalAxisDirection,
        mainAxis: mainAxis,
        delegate: delegate as TwoDimensionalChildBuilderDelegate,
        childManager: context as TwoDimensionalChildManager,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderGrid renderObject) {
    renderObject
      ..horizontalOffset = horizontalOffset
      ..horizontalAxisDirection = horizontalAxisDirection
      ..verticalOffset = verticalOffset
      ..verticalAxisDirection = verticalAxisDirection
      ..mainAxis = mainAxis
      ..delegate = delegate;
  }
}

class _RenderGrid extends RenderTwoDimensionalViewport {
  _RenderGrid({
    required super.horizontalOffset,
    required super.horizontalAxisDirection,
    required super.verticalOffset,
    required super.verticalAxisDirection,
    required TwoDimensionalChildBuilderDelegate delegate,
    required super.mainAxis,
    required super.childManager,
  }) : super(delegate: delegate);

  static const double _cell = 200;

  @override
  void layoutChildSequence() {
    final builder = delegate as TwoDimensionalChildBuilderDelegate;
    final columns = builder.maxXIndex! + 1;
    final rows = builder.maxYIndex! + 1;
    final h = horizontalOffset.pixels;
    final v = verticalOffset.pixels;
    for (var x = 0; x < columns; x++) {
      for (var y = 0; y < rows; y++) {
        final child = buildOrObtainChildFor(
          ChildVicinity(xIndex: x, yIndex: y),
        )!;
        child.layout(BoxConstraints.tight(const Size(_cell, _cell)));
        parentDataOf(child).layoutOffset = Offset(x * _cell - h, y * _cell - v);
      }
    }
    verticalOffset.applyContentDimensions(
      0,
      math.max(0, _cell * rows - viewportDimension.height),
    );
    horizontalOffset.applyContentDimensions(
      0,
      math.max(0, _cell * columns - viewportDimension.width),
    );
  }
}

/// The first box of [match] in global coordinates. [key] marks the widget
/// that draws the paragraph holding it.
Rect _matchRect(WidgetTester tester, Key key, FindMatch match) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.byKey(key), matching: find.byType(RichText)),
  );
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: match.start, extentOffset: match.end),
      )
      .first
      .toRect();
  return MatrixUtils.transformRect(paragraph.getTransformTo(null), box);
}

bool _inside(Rect inner, Rect outer) =>
    inner.left >= outer.left - 0.5 &&
    inner.right <= outer.right + 0.5 &&
    inner.top >= outer.top - 0.5 &&
    inner.bottom <= outer.bottom + 0.5;
