import 'package:find_in_page/find_in_page.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeSource implements FindableSource {
  _FakeSource(this.findableText);

  @override
  String findableText;

  @override
  Null get findableContext => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FindInPageController', () {
    test('finds matches across sources in registration order', () {
      final controller = FindInPageController();
      final first = _FakeSource('The cat sat on the mat.');
      final second = _FakeSource('The dog.');
      controller
        ..register(first)
        ..register(second)
        ..search('the');

      expect(controller.matchCount, 3);
      expect(controller.activeMatchIndex, 0);
      expect(controller.matchesFor(first), hasLength(2));
      expect(controller.matchesFor(second), hasLength(1));
    });

    test('is case insensitive by default, sensitive on request', () {
      final controller = FindInPageController()
        ..register(_FakeSource('The the THE'))
        ..search('the');
      expect(controller.matchCount, 3);

      controller.search('the', caseSensitive: true);
      expect(controller.matchCount, 1);
    });

    test('records correct offsets', () {
      final controller = FindInPageController();
      final source = _FakeSource('abc abc');
      controller
        ..register(source)
        ..search('abc');
      final matches = controller.matchesFor(source);
      expect(matches[0].start, 0);
      expect(matches[0].end, 3);
      expect(matches[1].start, 4);
      expect(matches[1].end, 7);
    });

    test('next and previous wrap around', () {
      final controller = FindInPageController()
        ..register(_FakeSource('a a a'))
        ..search('a');
      expect(controller.activeMatchIndex, 0);
      controller.next();
      expect(controller.activeMatchIndex, 1);
      controller.next();
      controller.next();
      expect(controller.activeMatchIndex, 0);
      controller.previous();
      expect(controller.activeMatchIndex, 2);
    });

    test('navigation is a no-op with no matches', () {
      final controller = FindInPageController()..search('missing');
      controller.next();
      controller.previous();
      expect(controller.activeMatchIndex, isNull);
      expect(controller.matchCount, 0);
    });

    test('clearSearch resets everything', () {
      final controller = FindInPageController()
        ..register(_FakeSource('hit hit'))
        ..search('hit');
      expect(controller.matchCount, 2);
      controller.clearSearch();
      expect(controller.matchCount, 0);
      expect(controller.query, isEmpty);
      expect(controller.activeMatchIndex, isNull);
    });

    test('empty query never matches', () {
      final controller = FindInPageController()
        ..register(_FakeSource('anything'))
        ..search('');
      expect(controller.matchCount, 0);
    });

    test('notifies listeners on search and navigation', () {
      final controller = FindInPageController()..register(_FakeSource('x x'));
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.search('x');
      controller.next();
      expect(notifications, 2);
    });
  });
}
