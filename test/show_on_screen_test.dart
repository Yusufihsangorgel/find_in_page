import 'package:find_in_page/src/auto_discovery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bringing a match into view, and the case where it cannot.
///
/// This is the last step of a find: the bar says 3 of 40 and the page has to
/// move. Nothing named it, and the interesting half is the early return --
/// a source whose render object is detached or unlaid-out happens routinely
/// while a list is scrolling, and throwing there would crash a search rather
/// than skip a row.
void main() {
  /// Finds the discovered source whose text starts with [prefix].
  RenderedTextSource sourceFor(WidgetTester tester, String prefix) {
    final root = tester.binding.rootElement!.renderObject!;
    return discoverTextSources(root)
        .firstWhere((s) => s.findableText.startsWith(prefix));
  }

  // A plain lazy `ListView` cannot host this test: measured, a target 2000px
  // down is not built at all until the viewport is close enough, and by the
  // time it is built it is already on screen. That gap is the reason
  // `FindableListView` exists. So the scrolling here goes through a
  // `SingleChildScrollView`, where everything is built and only visibility
  // changes -- which is what `showMatchOnScreen` is actually asked to fix.
  testWidgets('scrolls a viewport until the text is visible', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: const Column(
              children: [
                SizedBox(height: 2000),
                Text('needle down here'),
                SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      ),
    );
    expect(controller.offset, 0);
    expect(tester.getRect(find.text('needle down here')).top, greaterThan(600),
        reason: 'the target has to start off screen for this to mean anything');

    sourceFor(tester, 'needle').showMatchOnScreen(0, 6);
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
    final rect = tester.getRect(find.text('needle down here'));
    expect(rect.top, lessThan(600));
    expect(rect.bottom, greaterThan(0));
  });

  testWidgets('already-visible text is left where it is', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: const Column(
              children: [
                Text('needle at the top'),
                SizedBox(height: 3000),
              ],
            ),
          ),
        ),
      ),
    );
    final before = controller.offset;

    sourceFor(tester, 'needle').showMatchOnScreen(0, 6);
    await tester.pumpAndSettle();

    expect(controller.offset, before,
        reason: 'scrolling text that is already on screen would be a jolt');
  });

  testWidgets('a detached source returns instead of throwing', (tester) async {
    // The routine case: a row scrolls out of a lazy list between the sweep
    // that found it and the scroll that would reveal it. Throwing here would
    // take down the whole search over one stale row.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('needle then gone'))),
    );
    final stale = sourceFor(tester, 'needle');

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    expect(() => stale.showMatchOnScreen(0, 6), returnsNormally);
  });

  testWidgets('an out-of-range span does not throw either', (tester) async {
    // Offsets come from a search over text that may have changed since. The
    // guard is `boxes.isEmpty ? null : ...`, which asks the viewport to reveal
    // the whole object rather than a rectangle it could not compute.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('short'))),
    );

    expect(
      () => sourceFor(tester, 'short').showMatchOnScreen(400, 500),
      returnsNormally,
    );
  });
}
