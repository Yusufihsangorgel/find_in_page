import 'package:find_in_page/find_in_page.dart';
import 'package:find_in_page/src/highlight_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The overlay sits above the whole page, so nothing but its own code stops a
/// highlight from being drawn where the text has been scrolled out of sight.
const _findFill = Color(0xAA112233);
const _findActive = Color(0xBB445566);

const _bodyKey = ValueKey('body');
const _rowKey = ValueKey('row');

Widget _page(FindInPageController controller, Widget body) => MaterialApp(
      home: FindInPageScope(
        controller: controller,
        showBar: false,
        onOpenRequested: () {},
        highlightColor: _findFill,
        activeHighlightColor: _findActive,
        child: Scaffold(
          appBar: AppBar(title: const Text('acme docs')),
          body: body,
        ),
      ),
    );

/// Sixty short tiles, with the searched word only in those at [needles].
Widget _verticalList({
  Set<int> needles = const {1},
  ScrollController? scroll,
}) =>
    ListView(
      key: _bodyKey,
      controller: scroll,
      children: [
        for (var i = 0; i < 60; i++)
          ListTile(title: Text(needles.contains(i) ? 'needle $i' : 'row $i')),
      ],
    );

RenderHighlightOverlay _overlayOf(WidgetTester tester) =>
    tester.renderObject<RenderHighlightOverlay>(find.byType(HighlightOverlay));

/// The rectangle of the body's viewport, in the overlay's coordinates.
Rect _viewportRect(WidgetTester tester, RenderHighlightOverlay overlay) {
  final viewport = tester.renderObject<RenderBox>(
    find.descendant(of: find.byKey(_bodyKey), matching: find.byType(Viewport)),
  );
  return MatrixUtils.transformRect(
    viewport.getTransformTo(overlay),
    Offset.zero & viewport.size,
  );
}

/// Whether [actual] is [expected] after the float32 round trip that a
/// [Paint] applies to its colour.
bool _isColor(Color actual, Color expected) {
  const limit = 1 / 255;
  return (actual.a - expected.a).abs() < limit &&
      (actual.r - expected.r).abs() < limit &&
      (actual.g - expected.g).abs() < limit &&
      (actual.b - expected.b).abs() < limit;
}

/// Every highlight the overlay paints, as it would reach the canvas.
List<RRect> _highlights(RenderHighlightOverlay overlay) {
  final painted = <RRect>[];
  expect(
    overlay,
    paints
      ..everything((name, args) {
        if (name != #drawRRect) return true;
        final paint = args.last as Paint;
        if (_isColor(paint.color, _findFill) ||
            _isColor(paint.color, _findActive)) {
          painted.add(args.first as RRect);
        }
        return true;
      }),
  );
  return painted;
}

/// Whether [inner] lies inside [outer], allowing for float rounding.
bool _within(Rect inner, Rect outer) {
  const slack = 0.001;
  return inner.left >= outer.left - slack &&
      inner.top >= outer.top - slack &&
      inner.right <= outer.right + slack &&
      inner.bottom <= outer.bottom + slack;
}

void main() {
  group('highlight clipping', () {
    testWidgets('a match scrolled above the viewport paints nothing', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_page(controller, _verticalList()));
      controller.search('needle');
      await tester.pump();
      expect(controller.matchCount, 1);
      final overlay = _overlayOf(tester);
      expect(_highlights(overlay), hasLength(1));

      // The tile is 56 logical pixels tall and starts 56 down. Moving the
      // list up by 160 puts it wholly above the viewport, still inside the
      // cache extent so its render object stays alive under the app bar.
      await tester.drag(find.byKey(_bodyKey), const Offset(0, -160));
      await tester.pump();

      final tile = tester.getRect(find.text('needle 1', skipOffstage: false));
      final viewport = _viewportRect(tester, overlay);
      expect(tile.bottom, lessThan(viewport.top));

      final painted = _highlights(overlay);
      for (final rrect in painted) {
        expect(
          _within(rrect.outerRect, viewport),
          isTrue,
          reason: 'highlight ${rrect.outerRect} is outside $viewport',
        );
      }
      expect(painted, isEmpty);
    });

    testWidgets('a half visible match paints only the visible part', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      final scroll = ScrollController();
      addTearDown(scroll.dispose);

      await tester.pumpWidget(
        _page(controller, _verticalList(scroll: scroll)),
      );
      controller.search('needle');
      await tester.pump();
      final overlay = _overlayOf(tester);
      final viewport = _viewportRect(tester, overlay);
      final before = _highlights(overlay).single.outerRect;

      // Scroll exactly far enough to bring the middle of the text up to the
      // top edge of the viewport, so half of the highlight is above it.
      final text = tester.getRect(find.text('needle 1'));
      scroll.jumpTo(text.center.dy - viewport.top);
      await tester.pump();
      final moved = tester.getRect(find.text('needle 1'));
      expect(moved.top, lessThan(viewport.top));
      expect(moved.bottom, greaterThan(viewport.top));

      final painted = _highlights(overlay);
      expect(painted, hasLength(1));
      final after = painted.single.outerRect;
      expect(_within(after, viewport), isTrue);
      expect(after.top, closeTo(viewport.top, 0.001));
      expect(after.height, lessThan(before.height));
      expect(after.height, greaterThan(0));
    });

    testWidgets('only the visible one of two matches is painted', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _page(controller, _verticalList(needles: const {1, 8})),
      );
      controller.search('needle');
      await tester.pump();
      final overlay = _overlayOf(tester);
      expect(controller.matchCount, 2);
      expect(_highlights(overlay), hasLength(2));

      await tester.drag(find.byKey(_bodyKey), const Offset(0, -160));
      await tester.pump();

      // One highlight, exactly, and it sits on the tile that is still in view.
      final painted = _highlights(overlay);
      expect(painted, hasLength(1));
      final rect = painted.single.outerRect;
      expect(_within(rect, _viewportRect(tester, overlay)), isTrue);
      final text = tester.getRect(find.text('needle 8'));
      expect(rect.overlaps(text), isTrue);
      // The highlight covers the word, and is only a pixel larger all round.
      expect(rect.height, lessThan(text.height + 4));
    });

    testWidgets(
        'a match in a sideways list scrolled out of view paints '
        'nothing', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _page(
          controller,
          ListView(
            key: _bodyKey,
            children: [
              SizedBox(
                height: 80,
                child: ListView(
                  key: _rowKey,
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < 8; i++)
                      SizedBox(
                        width: 200,
                        child: Center(
                          child: Text(i == 0 ? 'needle 1' : 'cell $i'),
                        ),
                      ),
                  ],
                ),
              ),
              for (var i = 0; i < 20; i++) ListTile(title: Text('row $i')),
            ],
          ),
        ),
      );
      controller.search('needle');
      await tester.pump();
      final overlay = _overlayOf(tester);
      expect(_highlights(overlay), hasLength(1));

      // The cell is 200 wide. A 260 drag puts it wholly left of the row.
      // The cache extent keeps its render object alive just off screen.
      await tester.drag(find.byKey(_rowKey), const Offset(-260, 0));
      await tester.pump();

      final row = tester.getRect(find.byKey(_rowKey));
      final cell = tester.getRect(find.text('needle 1', skipOffstage: false));
      expect(cell.right, lessThan(row.left));

      expect(_highlights(overlay), isEmpty);
    });

    testWidgets('a match under a NaN transform paints nothing', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _page(
          controller,
          ListView(
            key: _bodyKey,
            children: [
              Transform(
                transform: Matrix4.identity()..setEntry(0, 0, double.nan),
                child: const Text('needle 1'),
              ),
              for (var i = 0; i < 20; i++) ListTile(title: Text('row $i')),
            ],
          ),
        ),
      );
      controller.search('needle');
      await tester.pump();
      expect(controller.matchCount, 1);

      expect(_highlights(_overlayOf(tester)), isEmpty);
    });
  });
}
