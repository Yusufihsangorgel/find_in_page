import 'package:find_in_page/find_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeSource implements FindableSource {
  _FakeSource(this.findableText);

  @override
  String findableText;

  @override
  Null get findableContext => null;
}

/// The two ways a widget reaches the controller, and the way it asks which
/// match is the active one.
///
/// `maybeOf` and `isActive` are the pieces a caller writing their own
/// highlighted widget uses, and neither was named in a test. Both have a
/// contract that is easy to change by accident: `maybeOf` returns null where
/// `of` throws, and `isActive` compares by identity rather than by value.
void main() {
  group('FindInPageScope.maybeOf', () {
    testWidgets('returns the controller of the enclosing scope',
        (tester) async {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      FindInPageController? seen;

      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: controller,
            child: Builder(
              builder: (context) {
                seen = FindInPageScope.maybeOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(seen, same(controller));
    });

    testWidgets('returns null with no scope above, rather than throwing', (
      tester,
    ) async {
      // This is the whole reason the method exists next to `of`. A widget that
      // works both inside and outside a find scope asks this one.
      Object? thrown;
      FindInPageController? seen;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              try {
                seen = FindInPageScope.maybeOf(context);
              } on Object catch (e) {
                thrown = e;
              }
              return const SizedBox();
            },
          ),
        ),
      );

      expect(thrown, isNull);
      expect(seen, isNull);
    });

    testWidgets('the scope above wins when scopes are nested', (tester) async {
      final outer = FindInPageController();
      final inner = FindInPageController();
      addTearDown(outer.dispose);
      addTearDown(inner.dispose);
      FindInPageController? seen;

      await tester.pumpWidget(
        MaterialApp(
          home: FindInPageScope(
            controller: outer,
            child: FindInPageScope(
              controller: inner,
              child: Builder(
                builder: (context) {
                  seen = FindInPageScope.maybeOf(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );

      expect(seen, same(inner), reason: 'nearest enclosing, not outermost');
    });
  });

  group('FindInPageController.isActive', () {
    test('is true for the active match and false for its neighbours', () {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final source = _FakeSource('cat cat cat');
      controller.register(source);
      controller.search('cat');

      final matches = controller.matchesFor(source);
      expect(matches, hasLength(3));
      expect(controller.isActive(matches[0]), isTrue);
      expect(controller.isActive(matches[1]), isFalse);

      controller.next();

      expect(controller.isActive(matches[0]), isFalse);
      expect(controller.isActive(matches[1]), isTrue);
    });

    test('compares by identity, so a rebuilt match list is not active', () {
      // `identical`, not `==`. A caller holding a match from before a research
      // must not have it light up: the offsets may line up while the text
      // underneath has moved. Swapping this for `==` would pass the test above
      // and fail this one.
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final source = _FakeSource('cat cat');
      controller.register(source);

      controller.search('cat');
      final before = controller.matchesFor(source).first;

      controller.search('');
      controller.search('cat');
      final after = controller.matchesFor(source).first;

      expect(controller.isActive(after), isTrue);
      expect(controller.isActive(before), isFalse,
          reason: 'the same offsets from an earlier search are a stale object');
    });

    test('nothing is active once the search is cleared', () {
      final controller = FindInPageController();
      addTearDown(controller.dispose);
      final source = _FakeSource('cat');
      controller.register(source);
      controller.search('cat');
      final match = controller.matchesFor(source).single;

      controller.clearSearch();

      expect(controller.activeMatch, isNull);
      expect(controller.isActive(match), isFalse);
    });
  });
}
