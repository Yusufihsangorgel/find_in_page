import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeSource implements FindableSource {
  _FakeSource(this.findableText);

  @override
  String findableText;

  @override
  Null get findableContext => null;
}

/// The two hooks a scope uses to drive the controller: installing the sweep
/// that finds unwrapped text, and telling it a source's text moved.
///
/// `FindInPageScope` calls both and the widget tests go through the scope, so
/// neither was ever named. Each carries a rule that is invisible from the call
/// site: discovery must not report text a registered source already owns, and
/// a text change with no search running must not schedule work.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('setDiscovery', () {
    test('finds text that nobody registered', () async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final loose = _FakeSource('a cat in the sweep');
      controller.setDiscovery(() => [loose]);

      controller.search('cat');

      expect(controller.matchCount, 1);
      expect(controller.matchesFor(loose), hasLength(1));
    });

    test('does not count a registered source twice', () async {
      // The rule the doc states: a FindableText both registers itself and
      // renders a paragraph the sweep can see. Counting both would double
      // every match on the page, and the count is what the find bar shows.
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final source = _FakeSource('cat cat');
      controller.register(source);
      controller.setDiscovery(() => [source]);

      controller.search('cat');

      expect(controller.matchCount, 2, reason: 'two in the text, not four');
    });

    test('passing null leaves only what registered itself', () async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final registered = _FakeSource('cat');
      final swept = _FakeSource('cat cat cat');
      controller.register(registered);
      controller.setDiscovery(() => [swept]);

      controller.search('cat');
      expect(controller.matchCount, 4);

      controller.setDiscovery(null);
      controller.search('');
      controller.search('cat');

      expect(controller.matchCount, 1);
    });

    test('the callback runs per recompute, not once at install', () async {
      // It is installed before layout and read after it, so a sweep that
      // cached its answer would report last frame's widgets.
      var calls = 0;
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      controller.setDiscovery(() {
        calls++;
        return [_FakeSource('cat')];
      });

      expect(calls, 0, reason: 'installing must not sweep');

      controller.search('cat');
      final afterFirst = calls;

      controller.search('ca');

      expect(afterFirst, greaterThan(0));
      expect(calls, greaterThan(afterFirst));
    });
  });

  // `sourceTextChanged` schedules its recompute in a post-frame callback and
  // deliberately does not ask for a frame of its own. That is right for how it
  // is called -- from a source whose widget just rebuilt, so a frame is
  // already in flight and the recompute lands at the end of it -- but it means
  // the method does nothing at all in a test that only calls it.
  //
  // Measured: with a root pumped and no rebuild, `tester.pump()` leaves the
  // callback sitting there, and a second pump does not help either. So these
  // drive a real rebuild, which is also the only setup that matches how the
  // method reaches the controller in an app.
  group('sourceTextChanged', () {
    testWidgets('re-finds against the new text', (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final source = _FakeSource('one cat');
      controller.register(source);
      controller.search('cat');
      expect(controller.matchCount, 1);

      await _rebuildWith(tester, () {
        source.findableText = 'cat cat cat';
        controller.sourceTextChanged(source);
      });

      expect(controller.matchCount, 3);
    });

    testWidgets('does nothing while no search is running', (tester) async {
      // The guard is `if (_query.isNotEmpty)`. Text changes constantly in a
      // live app; recomputing on every one of them with no query on screen
      // would be work nobody asked for.
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final source = _FakeSource('cat');
      controller.register(source);

      var notifications = 0;
      controller.addListener(() => notifications++);

      await _rebuildWith(tester, () {
        source.findableText = 'cat cat';
        controller.sourceTextChanged(source);
      });

      expect(notifications, 0);
      expect(controller.matchCount, 0);
    });

    testWidgets('a source that lost its matches drops out of the count', (
      tester,
    ) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final kept = _FakeSource('cat');
      final emptied = _FakeSource('cat');
      controller
        ..register(kept)
        ..register(emptied);
      controller.search('cat');
      expect(controller.matchCount, 2);

      await _rebuildWith(tester, () {
        emptied.findableText = 'nothing here';
        controller.sourceTextChanged(emptied);
      });

      expect(controller.matchCount, 1);
      expect(controller.matchesFor(emptied), isEmpty);
    });
  });
}

/// Runs [change] inside a real rebuild, the way a source does.
///
/// A `FindableText` whose text changed is rebuilding when it tells the
/// controller, so the post-frame recompute rides the frame that is already
/// happening. Pumping a fresh tree reproduces that; calling the method on its
/// own does not.
Future<void> _rebuildWith(WidgetTester tester, VoidCallback change) async {
  await tester.pumpWidget(const SizedBox());
  change();
  await tester.pumpWidget(const SizedBox(key: ValueKey('after')));
}
