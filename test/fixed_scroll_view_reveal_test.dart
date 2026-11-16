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
  testWidgets('turns a PageView to the page holding the match', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = FindInPageController();
    final pages = PageController();
    addTearDown(controller.dispose);
    addTearDown(pages.dispose);

    const needles = {1, 3};
    await tester.pumpWidget(
      MaterialApp(
        home: FindInPageScope(
          controller: controller,
          child: Scaffold(
            body: PageView(
              controller: pages,
              children: [
                for (var i = 0; i < 4; i++)
                  _KeptAlive(
                    // The match ends in the first half of its page. Scrolling
                    // only until it shows would stop short of half a page,
                    // and the PageView would settle back on the one before.
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
    // A page is built once it has been shown, and kept after that, as tabs a
    // user has opened are.
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
      final rect = _matchRect(tester, ValueKey(page), match);
      expect(_inside(rect, view), isTrue, reason: '$name: $rect');
    }

    await step(() => controller.search('needle'), 'search, page 1');
    await step(controller.next, 'next, page 3');
    await step(controller.next, 'next wraps to page 1');
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
